# CI/CD Lab — Review Q&A

Notes from the review session after building a GitHub Actions pipeline for the Terraform local lab (fmt, validate, plan on pull requests, branch protection, secret masking).

---

### 1. What's the difference between a trigger, a job, and a step?

A **trigger** is the event that starts the workflow — a `push`, a `pull_request`, a schedule, or a manual run. A **job** is a collection of steps that runs on a single runner (machine). A **step** is a single command or action executed within a job — checking out code, running a CLI command, or using a reusable action. A workflow can have one trigger and multiple jobs, and each job has its own sequence of steps.

---

### 2. Why did the pipeline not run after the first push, and again after the Step 7 workflow edit — what did both cases have in common?

Both times, the `on:` trigger used a `paths:` filter restricting the workflow to only run when files under `02-terraform-local/**` changed. The first push only touched the workflow file itself (`.github/workflows/terraform-ci.yml`), which didn't match that path — so GitHub correctly evaluated the condition and skipped the run. The same thing happened again when editing the workflow file for the secrets demo. The fix was adding `.github/workflows/**` to the `pull_request` path filter as well, so changes to the pipeline definition itself would also trigger it. Lesson: path filters are evaluated literally against the diff, not against "did anything in the repo change."

---

### 3. What happened when the formatting was broken on purpose, and why didn't `init`/`validate`/`plan` run afterward?

The `Terraform Format Check` step (`terraform fmt -check -recursive`) detected that the code didn't match standard formatting and returned a failing exit code. By default, GitHub Actions stops a job immediately when a step fails, and skips every step that comes after it in that job. So `init`, `validate`, and `plan` weren't run and didn't "fail" either — they never got the chance to execute at all. This is intentional: there's no value in validating or planning code that isn't even correctly formatted. (This default can be overridden per step with `continue-on-error: true`, but stop-on-first-failure is the sensible default for this kind of check.)

---

### 4. Why does `plan` output get posted in the pipeline log instead of running `apply` directly?

`apply` makes real changes, so it's deliberately kept as a separate, later step — often behind a manual approval gate — rather than running automatically on every pull request. Posting the `plan` output in the pipeline log is what makes **human review meaningful**: a reviewer can see exactly what will be created, changed, or destroyed before the code is even merged, let alone applied. If `apply` ran automatically on every PR, infrastructure changes could happen before anyone had looked at them — which defeats the point of having a review process at all.

---

### 5. What did the secret masking demonstrate, and why does that matter once using real Azure credentials?

GitHub Actions automatically detects any string in a step's output that matches a registered secret's value and redacts it in the logs, replacing it with `***` — even if a command (like `echo`) tries to print it directly. This means secrets can safely be referenced in workflow commands without their real values leaking into logs that might be visible to other collaborators or stored long-term in run history. This is exactly the mechanism that will be used later for real credentials — e.g. an Azure service principal client secret — allowing the pipeline to authenticate to Azure without exposing that secret anywhere in the visible output.

---

*Lab covered: GitHub Actions workflow structure, path-based triggers, `fmt`/`validate`/`plan` as pipeline steps, stop-on-failure behavior, branch protection requiring checks to pass, and secret masking — including troubleshooting two real trigger-path issues.*
