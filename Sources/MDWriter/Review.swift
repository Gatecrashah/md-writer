import Foundation

/// What the review should look at. Raw values are the lens names the `writing-review` skill defines.
enum ReviewLens: String, CaseIterable {
    case lineEdit = "line-edit"
    case structure
    case skepticalReader = "skeptical-reader"
    case aiPatterns = "ai-patterns"

    var title: String {
        switch self {
        case .lineEdit: "Line edit"
        case .structure: "Structure"
        case .skepticalReader: "Skeptical reader"
        case .aiPatterns: "AI patterns"
        }
    }
}

/// Model aliases accepted by `claude --model`; aliases track the latest version of each model.
enum ReviewModel: String, CaseIterable {
    case sonnet, opus, fable, haiku

    var title: String { rawValue.capitalized }
}

struct ReviewRequest {
    var lens: ReviewLens
    var model: ReviewModel
    var note: String
}

/// The review as the skill returns it; `reviewSchema` is the JSON Schema for the same shape.
struct Review: Codable {
    var summary: String
    var findings: [Finding]
}

struct Finding: Codable {
    enum Kind: String, Codable { case edit, comment, question }
    var kind: Kind
    /// Exact plain text from the draft the finding is about; empty for a note on the whole document.
    var quote: String
    var message: String
    /// Text that replaces `quote` when the author applies an `edit`.
    var replacement: String?
}

private let reviewSchema = """
{"type":"object","additionalProperties":false,"required":["summary","findings"],"properties":{
"summary":{"type":"string"},
"findings":{"type":"array","items":{"type":"object","additionalProperties":false,
"required":["kind","quote","message"],"properties":{
"kind":{"enum":["edit","comment","question"]},"quote":{"type":"string"},
"message":{"type":"string"},"replacement":{"type":"string"}}}}}}
"""

/// The JSON object `claude -p --output-format json` prints.
private struct CLIResult: Decodable {
    var isError: Bool
    var result: String?
    var sessionID: String?
    var structuredOutput: Review?

    enum CodingKeys: String, CodingKey {
        case isError = "is_error", result, sessionID = "session_id", structuredOutput = "structured_output"
    }
}

enum ReviewError: LocalizedError {
    case cancelled
    case skillMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "The review was cancelled."
        case .skillMissing: "The writing-review skill is missing from the app bundle. Rebuild with scripts/build-app.sh."
        case .failed(let detail): detail
        }
    }
}

/// Runs one review round as a background `claude -p` process.
final class ReviewRunner {
    private var process: Process?
    private var cancelled = false

    /// Starts the review. `completion` runs on the main queue with the review and its session ID.
    /// Passing `resume` continues that session, so Claude remembers earlier rounds.
    func start(markdown: String, prompt: String, model: ReviewModel, resume sessionID: String?,
               completion: @escaping (Result<(Review, String), ReviewError>) -> Void) {
        let finish = { result in DispatchQueue.main.async { completion(result) } }
        let workDir: URL
        do { workDir = try Self.prepareWorkingDirectory() } catch {
            return finish(.failure(error as? ReviewError ?? .failed(error.localizedDescription)))
        }

        var args = ["-p", "--output-format", "json", "--json-schema", reviewSchema,
                    "--model", model.rawValue, "--tools", "Skill", "--setting-sources", "project"]
        if let sessionID { args += ["--resume", sessionID] }
        args.append(prompt)

        // Apps launched from Finder get a minimal PATH; a login shell finds `claude` where the terminal does.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec claude \"$@\"", "claude"] + args
        process.currentDirectoryURL = workDir
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        self.process = process

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do { try process.run() } catch {
                return finish(.failure(.failed("Couldn't start Claude: \(error.localizedDescription)")))
            }
            var errData = Data()
            let errRead = DispatchWorkItem { errData = stderr.fileHandleForReading.readDataToEndOfFile() }
            DispatchQueue.global().async(execute: errRead)
            stdin.fileHandleForWriting.write(Data(markdown.utf8))
            try? stdin.fileHandleForWriting.close()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            errRead.wait()
            process.waitUntilExit()

            if cancelled { return finish(.failure(.cancelled)) }
            finish(Self.parse(out: outData, err: errData, status: process.terminationStatus))
        }
    }

    func cancel() {
        cancelled = true
        process?.terminate()
    }

    deinit { process?.terminate() }

    private static func parse(out: Data, err: Data, status: Int32) -> Result<(Review, String), ReviewError> {
        guard let cli = try? JSONDecoder().decode(CLIResult.self, from: out) else {
            let detail = String(decoding: err.isEmpty ? out : err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed("claude exited with status \(status).\n\n\(detail.suffix(1000))"))
        }
        guard !cli.isError, let review = cli.structuredOutput, let sessionID = cli.sessionID else {
            return .failure(.failed(cli.result ?? "Claude returned no review."))
        }
        return .success((review, sessionID))
    }

    /// A fixed working directory keeps `--resume` working (sessions are stored per directory)
    /// and gives `claude` a project-level copy of the bundled skill.
    private static func prepareWorkingDirectory() throws -> URL {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("skills/writing-review"),
              FileManager.default.fileExists(atPath: bundled.path) else { throw ReviewError.skillMissing }
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MD Writer/Review")
        let skills = dir.appendingPathComponent(".claude/skills")
        try fm.createDirectory(at: skills, withIntermediateDirectories: true)
        let dest = skills.appendingPathComponent("writing-review")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: bundled, to: dest)
        return dir
    }
}

/// One document's review history, kept so later rounds can resume the same Claude session.
struct ReviewThread {
    enum Outcome: String { case applied, dismissed }

    var request: ReviewRequest
    var sessionID: String?
    var round = 0
    /// Findings of the latest round, keyed by the ID the editor uses.
    var findings: [String: Finding] = [:]
    var outcomes: [String: Outcome] = [:]

    /// The prompt for the next round. Later rounds tell Claude what the author did with its findings.
    func prompt() -> String {
        var lines = ["Use the writing-review skill. Lens: \(request.lens.rawValue)."]
        if !request.note.isEmpty { lines.append("Author's note: \(request.note)") }
        if round > 0 {
            lines.append("The author revised the draft. What happened to your previous findings:")
            for (id, f) in findings.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
                switch outcomes[id] {
                case .applied: lines.append("- Applied: \"\(f.quote)\" → \"\(f.replacement ?? "")\"")
                case .dismissed: lines.append("- Dismissed: \"\(f.quote)\" (\(f.message))")
                case nil: lines.append("- Left open: \"\(f.quote)\" (\(f.message))")
                }
            }
        }
        lines.append("The draft is on stdin.")
        return lines.joined(separator: "\n")
    }
}
