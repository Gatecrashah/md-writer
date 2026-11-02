## Why we moved off cron

In today's fast-paced world, scheduled jobs are a **crucial** part of any backend. Our nightly sync ran on cron for three years and it was, frankly, fine.

It's not just about reliability — it's about visibility. When a job failed, nobody knew until a customer emailed us.

We decided to move to a queue.
