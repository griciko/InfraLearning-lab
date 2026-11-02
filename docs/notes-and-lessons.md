# Notes and Lessons — Week 1

Infrastructure as Code fundamentals: Git, Terraform, CI/CD, Ansible — all learned without a cloud provider, using local/random/Docker providers for Terraform and `localhost` for Ansible. Each topic has its own detailed `review-qa.md` in its folder; this file is the cross-topic summary and the practical lessons that came from real troubleshooting, not just the planned exercises.

---

## Git

- Local vs. remote: working directory → staging area → repository (local), then push/pull to GitHub (remote).
- Branching and pull requests are the normal way to make changes — not committing straight to `main`.
- `reset` rewrites history (safe only on unshared commits); `revert` adds a new commit that undoes a previous one (safe on shared/pushed history).
- `rebase` replays commits for a linear history but rewrites hashes — never rebase commits already pushed and shared.
- `stash` shelves uncommitted changes temporarily when switching branches without committing half-done work.
- `fetch` downloads remote changes without touching local files; `pull` is `fetch` + `merge` in one step.

**Real issue hit:** `! [rejected] ... non-fast-forward` on first push, caused by creating the GitHub repo with an auto-generated README while already having a local one — two unrelated histories. Fixed with `git pull origin main --allow-unrelated-histories` and resolving the resulting conflict manually.

**Real issue hit (again, later):** a second `fetch first` rejection after mixing GitHub web UI merges (pull requests merged in the browser) with local commits — this time a normal case of remote being ahead, fixed with a plain `git pull origin main`.

**Lesson:** always `git pull` before pushing, especially when merging PRs through the GitHub UI in the same session as committing locally — the two histories diverge easily.

---

## Terraform

- Declarative model: code defines desired state, state file (`.tfstate`) records what Terraform believes exists, and `plan`/`apply` reconcile the two.
- Workflow: `init` → `fmt` → `validate` → `plan` → `apply` → `destroy`. `plan` is the non-negotiable habit before every `apply`.
- Variables, outputs, and `.tfvars` make code reusable across environments.
- `count` creates multiples of a resource from one block.
- Modules package reusable groups of resources — called multiple times with different inputs instead of duplicating code.
- Drift = reality no longer matches the state Terraform expects (detected on the next `plan`), whether that's a hand-edited file or a manually stopped Docker container.

**Real issue hit:** replacing `main.tf` entirely (instead of merging new blocks into it) caused `local_file.hello` to disappear from the code while still existing in state — Terraform read that as "no longer desired" and deleted the real file on `apply`.

**Lesson:** if a resource isn't in the code, Terraform doesn't ignore it — it's treated as *should not exist* and gets destroyed. There's no middle ground. Always read `plan` output for unexpected deletes (`-`), not just check that creates look right. This applies just as much to `plan -destroy` output, which should be read as an approval request for irreversible changes.

**Real issue hit:** Docker Desktop installed but engine not running (`failed to connect to the docker API`) — resolved by waiting for full Docker Desktop startup and a restart.

---

## CI/CD (GitHub Actions)

- A pipeline (GitHub calls it a "workflow") is an automated, staged sequence with triggers, jobs, and steps — not just "a script that runs."
- Workflow files must live in `.github/workflows/` at the **repo root**, regardless of which subfolder they operate on.
- `paths:` filters control exactly which file changes trigger a run — evaluated literally against the diff, not "did anything in the repo change."
- By default, a failed step stops the job immediately and skips everything after it in that job (e.g. a failed `fmt -check` meant `init`/`validate`/`plan` never ran).
- `plan` output belongs in the pipeline log specifically so a human can review real changes before merge — `apply` is deliberately a separate, later, gated step.
- Branch protection rules can require a check to pass before a PR is allowed to merge, turning the pipeline from informational into enforced.
- Secrets referenced in workflow commands are automatically masked (`***`) in logs, even if a command tries to print them directly.

**Real issue hit:** pipeline didn't trigger twice — once on the very first push (only the workflow file changed, not `02-terraform-local/**`), and again later when editing the workflow for the secrets demo (same cause). Fixed by adding `.github/workflows/**` to the `pull_request` path filter.

**Lesson:** path filters apply to *every* trigger context, including changes to the pipeline definition itself — not just the application/infra code it's meant to watch.

---

## Ansible

- Terraform provisions infrastructure; Ansible configures what's already there (packages, files, services) — different responsibilities, often used together.
- No state file — idempotency is checked fresh on every run, per module (e.g. `apt` checks if a package is already installed; `copy` compares file content).
- `become: true` escalates privileges (like `sudo`) — but anything created while escalated is owned by root on disk, and needs `sudo` again later to modify or delete manually.
- Handlers only run when notified by another task, and only fire once per play even if notified multiple times — and they won't fire at all if the notifying task reports no change.
- The `command`/`shell` modules don't print their output to the terminal automatically — use `register` + `debug` to actually see command output.
- `--check` is a dry run, the direct equivalent of `terraform plan` (and conceptually similar to PowerShell's `-WhatIf`).

**Real issue hit:** `Permission denied` trying to `echo >>` and later `rm -rf` files that Ansible had created with `become: true` — the files were root-owned. Fixed with `sudo rm -rf` to match how they were created.

**Lesson:** privilege escalation in Ansible has the same real-world consequences as running `sudo` manually — including file ownership outliving the playbook run.

---

## Cross-topic patterns worth remembering

- **"Read the plan/log before confirming"** shows up everywhere: `terraform plan`, `plan -destroy`, Ansible `--check`, and CI pipeline logs. The tools are good at showing you what's about to happen — the discipline is actually reading it.
- **Declarative tools treat absence as intent.** Remove something from Terraform code → it gets destroyed. This is different from imperative scripting, where not mentioning something means "leave it alone."
- **State vs. stateless**: Terraform tracks a state file and reconciles against it; Ansible has no state file and checks the live system fresh each run. Different mechanisms, same idempotent goal.
- **Permissions and ownership follow how something was created** — whether that's a root-owned file from `become: true`, or a GitHub Actions secret that's masked specifically because of how it's injected at runtime.
- **Git conflicts and CI path filters are both "comparing two versions of truth"** — a merge conflict is two branches disagreeing on a file; a path filter mismatch is the trigger disagreeing with what actually changed. Both needed the same debugging instinct: check what actually differs before assuming the tool is broken.

---

## What's next

- Azure fundamentals and the free/trial subscription
- First real Terraform deployment on Azure (VM, resource group, networking)
- Remote state (Azure Storage backend)
- Entra ID with Terraform (`azuread` provider)
- Intune trial and Intune-as-code (Graph-based providers)
- Tying CI/CD into a real `apply` step with approval gates, once there's a real cloud target

---

## AWS week (Days 1-4)

### Day 1: first EC2 instance
- Never use the root account for daily work: an IAM user with an access key does the CLI and Terraform work
- A security group restricts source and port: SSH from my IP only, not `0.0.0.0/0`
- Terraform builds the creation order from references in the code (security group before instance)
- SSH on Windows rejects a `.pem` with overly open permissions: fixed by removing broad entries with `icacls`
- EventBridge cannot publish to an SNS topic without a topic policy
- Stopped = no compute billing but EBS storage still billed. Terminated = gone

### Day 2: Terraform + Ansible together
- The "integration" is a file: Terraform writes `inventory.ini`, Ansible reads it
- `/mnt/d/` in WSL does not support `chmod`: copy the key into `~/.ssh/` inside WSL
- Testing found a missing port 80 rule: the code must describe what is actually needed
- Edit the playbook, never the live server: manual edits get overwritten on the next run
- EC2 public IPs change on stop/start: re-run `terraform apply`, or use an Elastic IP

### Day 3: Windows instance and remote state
- Remote state fixes loss, sharing, locking and storage of secrets. The bucket is bootstrapped once outside the project
- Terraform does not roll back a failed apply: what succeeded stays, and a re-run creates only what is missing
- `plan` can pass while `apply` fails on account-level restrictions (instance type on a Free Tier account)
- Windows password decryption needs an RSA key pair: ED25519 can sign but cannot encrypt or decrypt
- A new state version is written on every state write, and lock files appear in the version list

### Day 4: snapshots, backup and restore
- A snapshot is a copy of a volume, not an instance. Machine = configuration + disks
- Restores are point-in-time, and `mkfs` on a restored volume erases the data
- A backup must not share a lifecycle with what it protects: policy in Terraform, data in a vault
- Deregister an AMI before deleting its snapshot, and delete the snapshot too
- RPO is the acceptable data loss, RTO is the acceptable downtime, and a restore test measures the real time

### Cross-topic
- Lab vs. production is a real difference: know it and say it plainly
- Rule of thumb for automation: if I would do it twice, it goes into a playbook. SSH is for checking only