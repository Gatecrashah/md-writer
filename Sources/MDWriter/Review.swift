import Foundation

/// A skill bundled in the app's `skills` folder that can review a draft.
struct Reviewer: Equatable {
    /// The skill's name, as Claude invokes it.
    var name: String
    var description: String
    /// The folder holding the skill's `SKILL.md` and any files it references.
    var directory: URL

    static let defaultName = "writing-review"

    /// "plain-writing" → "Plain writing".
    var title: String {
        let words = name.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// The bundled reviewers, by name.
    static func available() -> [Reviewer] {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("skills"),
              let dirs = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else { return [] }
        return dirs.compactMap { dir in
            guard let text = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8)
            else { return nil }
            let meta = frontmatter(text)
            return Reviewer(name: meta["name"] ?? dir.lastPathComponent, description: meta["description"] ?? "",
                            directory: dir)
        }.sorted { $0.name < $1.name }
    }

    /// The top-level `key: value` pairs of a SKILL.md's leading `---` block. Folded values (`>-`, `|`)
    /// are joined into one line.
    private static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var meta: [String: String] = [:]
        var folding: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let key = folding, line.first == " " {
                let part = line.trimmingCharacters(in: .whitespaces)
                meta[key] = meta[key].map { $0.isEmpty ? part : "\($0) \(part)" }
                continue
            }
            folding = nil
            guard line.first != " ", let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if [">", ">-", "|", "|-"].contains(value) {
                folding = key
                meta[key] = ""
            } else {
                meta[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return meta
    }
}

/// Model aliases accepted by `claude --model`; aliases track the latest version of each model.
enum ReviewModel: String, CaseIterable {
    case sonnet, opus, fable, haiku

    var title: String { rawValue.capitalized }
}

struct ReviewRequest {
    var reviewer: Reviewer
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
    struct ModelUsage: Decodable { var outputTokens: Int }

    var isError: Bool
    var result: String?
    var sessionID: String?
    var structuredOutput: Review?
    /// Usage keyed by exact model ID, e.g. `claude-opus-5-5`.
    var modelUsage: [String: ModelUsage]?

    enum CodingKeys: String, CodingKey {
        case isError = "is_error", result, sessionID = "session_id", structuredOutput = "structured_output"
        case modelUsage
    }
}

struct ReviewResult {
    var review: Review
    var sessionID: String
    /// The exact model that wrote the review, when Claude Code reports it.
    var modelID: String?
}

/// Turns a model ID into a name for display: `claude-opus-5-5` → "Opus 5.5",
/// `claude-sonnet-4-5-20250929` → "Sonnet 4.5", `claude-3-5-haiku-20241022` → "Haiku 3.5".
/// IDs in any other shape are returned unchanged.
func readableModelName(_ id: String) -> String {
    let parts = id.split(separator: "-").map(String.init)
    guard parts.first == "claude" else { return id }
    let rest = parts.dropFirst().filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
    let family = rest.filter { !$0.allSatisfy(\.isNumber) }
    let version = rest.filter { $0.allSatisfy(\.isNumber) }
    guard family.count == 1, !version.isEmpty else { return id }
    return "\(family[0].capitalized) \(version.joined(separator: "."))"
}

enum ReviewError: LocalizedError {
    case cancelled
    case skillMissing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "The review was cancelled."
        case .skillMissing(let name): "The \(name) skill is missing. If it's the bundled one, rebuild with scripts/build-app.sh."
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
    func start(markdown: String, prompt: String, reviewer: Reviewer, model: ReviewModel, resume sessionID: String?,
               completion: @escaping (Result<ReviewResult, ReviewError>) -> Void) {
        let finish = { result in DispatchQueue.main.async { completion(result) } }
        let workDir: URL
        do { workDir = try Self.prepareWorkingDirectory(with: reviewer) } catch {
            return finish(.failure(error as? ReviewError ?? .failed(error.localizedDescription)))
        }

        var args = ["-p", "--output-format", "json", "--json-schema", reviewSchema,
                    "--model", model.rawValue, "--tools", "Skill,Read", "--setting-sources", "project"]
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

    private static func parse(out: Data, err: Data, status: Int32) -> Result<ReviewResult, ReviewError> {
        guard let cli = try? JSONDecoder().decode(CLIResult.self, from: out) else {
            let detail = String(decoding: err.isEmpty ? out : err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed("claude exited with status \(status).\n\n\(detail.suffix(1000))"))
        }
        guard !cli.isError, let review = cli.structuredOutput, let sessionID = cli.sessionID else {
            return .failure(.failed(cli.result ?? "Claude returned no review."))
        }
        let modelID = cli.modelUsage?.max { $0.value.outputTokens < $1.value.outputTokens }?.key
        return .success(ReviewResult(review: review, sessionID: sessionID, modelID: modelID))
    }

    /// A fixed working directory keeps `--resume` working (sessions are stored per directory). It holds a
    /// copy of the chosen skill and nothing else, so Claude can read the skill's own files but no other skills.
    private static func prepareWorkingDirectory(with reviewer: Reviewer) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: reviewer.directory.appendingPathComponent("SKILL.md").path) else {
            throw ReviewError.skillMissing(reviewer.name)
        }
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MD Writer/Review")
        let skills = dir.appendingPathComponent(".claude/skills")
        try? fm.removeItem(at: skills)
        try fm.createDirectory(at: skills, withIntermediateDirectories: true)
        try fm.copyItem(at: reviewer.directory, to: skills.appendingPathComponent(reviewer.name))
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
    /// The output rules are here rather than in the skill, so any skill can be the reviewer.
    func prompt() -> String {
        var lines = [
            "Use the \(request.reviewer.name) skill to review the draft on stdin. Only review: don't rewrite the "
                + "draft or change any files. Report what the skill would change or question as findings:",
            "- kind \"edit\" with a replacement for each concrete change; \"comment\" for advice the author must act "
                + "on; \"question\" for what only the author knows. Use \"\" as the replacement to delete the quote.",
            "- quote: the exact passage as it reads, without Markdown syntax, inside one paragraph, heading or list "
                + "item, and long enough to be unique. Use \"\" only for a note on the whole document.",
            "- Never add facts, numbers, names or claims the draft doesn't contain. If a fix needs them, ask a "
                + "question instead.",
            "- At most 12 findings, most important first. summary: the single most important thing to do next.",
        ]
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
