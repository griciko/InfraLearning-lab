# Day 5 — Session Review (step by step)

A chronological review of the whole Day 5 session. Command-level detail is in `steps-summary.md`, and the question-by-question notes are in `review-qa.md`.

**Status reminder:** everything here is lab work in a personal AWS account, not production experience.

---

## 1. Preparation

1. Confirmed the AWS CLI was authenticated and the repo was up to date (`git pull`, clean `git status`).
2. Confirmed the Ansible collections `community.general` and `ansible.posix` were available in WSL.
3. Confirmed nothing was running from Day 4.
4. Agreed the plan: wrap-up, PowerShell, then the AWS Backup lab, with **Ansible doing the OS-level work** (new rule: if something is done twice it goes into a playbook, and SSH is for looking only).

---

## 2. Part 1 — Wrap-up

- Updated the README status table, added the lab-vs-production banner, extended the notes file with the AWS week.
- Searched the repo and its history for personal data. Findings: a tracked Week 1 inventory (localhost only), the public IP in Day 1-2 `main.tf`, key names in Day 1-3 `main.tf`.
- Decision: move values into variables with a Git-ignored `terraform.tfvars`, and use the standard file layout from the Azure phase on.

---

## 3. Part 2 — PowerShell

- Built `check-aws-leftovers.ps1` in five blocks (parameters, helper functions, list of checks, loop with `try/catch`, summary with exit codes), then tested the clean case, a deliberate leftover, and the failure path.
- Extra: a GitHub Actions workflow that runs the script. This led to the exit-code explanation and to replacing stored credentials with a **read-only IAM user** (least privilege).
- Correction from my side earlier in the session: an Elastic IP is no longer free while attached. AWS charges for public IPv4 addresses in general.

---

## 4. Part 3 — AWS Backup lab

| # | Step | Key result |
|---|---|---|
| 1 | Platform project: vault, role, two policy attachments, plan, tag-based selection | 6 resources, `force_destroy` unset on purpose |
| 2 | Workload project: instance, security group, tagged data volume, attachment, inventory | The tag is the only backup-related thing |
| 3 | Ansible prepared the data disk, using the volume ID for the device path | Second run changed nothing |
| 4 | On-demand backup job | Completed in 1-2 minutes, recovery point 68.5 MB |
| 5 | Destroyed the workload only | The recovery point survived in the vault |
| 6 | Restore: metadata (AZ empty), AZ fallback, restore job with copied tags | Job 01:58 |
| 7 | Rebuilt the workload with the restored volume (no new volume in the plan) | Rebuild 08:37 |
| 8 | Read-only verify playbook | Original file and timestamp came back, verification 02:26 |
| 9 | Timing against a self-defined RTO | Total 13:02, recovery point age 11:37:35 |
| 10 | Cleanup, leftovers script before and after | Final result CLEAN, exit code 0 |

---

## 5. Review and corrections

- **Backup lab review:** the platform/workload split, trust policy vs. attached policies, why the playbook uses the volume ID, why the recovery point survived, and what the on-demand job did not test. Correction on the first answer: the volume is created and attached in the **workload** project, and the two projects are linked only by the tag.
- **Restore review:** the read-only playbook, the phases of recovery time, and RPO. **Correction on RPO:** the backup interval must be at most the RPO (worst case), not twice it, so a 4-hour RPO needs an interval of 4 hours at most, and in practice tighter.
- **Who deleted the restored volume:** the answer was first "Terraform", but the code says otherwise (`count = 0`, the attachment only detaches). CloudTrail settled it: the call came from `aws-cli` (`ec2.delete-volume`), the manual delete. This also showed that the audit trail identifies **which tool** made a call. The correct sequence: the leftovers script after the destroy listed the unattached restored volume and the snapshot, as predicted, and the volume was then deleted by hand. The earlier report that only the snapshot remained was a mix-up.

---

## 6. Documents produced

| File | Where to put it | Purpose |
|---|---|---|
| `day5-steps.md` | `06-aws/day5-docs/steps-summary.md` | Command-level steps for the three parts |
| `day5-review-qa.md` | `06-aws/day5-docs/review-qa.md` | Review answers with corrections, plus the lab-vs-production table |
| `day5-session-review.md` | `06-aws/day5-docs/session-review.md` | This chronological review |
| `aws-azure-mapping.md` (updated) | `docs/aws-azure-mapping.md` | Scenario 6 now done on AWS, with a new section on what the lab showed |

The two Terraform projects (`day5-backup-platform`, `day5-backup-workload`) and the PowerShell script keep their own folders.

---

## 7. Key lessons

- Exit codes are how scripts talk to pipelines: 0 = fine, anything else = look
- CI credentials should be least privilege: a read-only job gets a read-only user
- Backup **policy** and workload live in separate projects, linked only by a tag, so the backup outlives its source
- A restore job creates resources **outside** your IaC: adopt or delete them
- Identify disks by volume ID, never by `nvme1n1`
- A restore check must be read-only, or it can hide a failed restore
- RPO is judged on the worst case: the backup interval must be at most the RPO
- The restore job is only one phase of recovery time, and prepared automation shrinks the rest
- The audit trail answers "who did this and with which tool"
- Terraform doesn't remove what it didn't create

---

## 8. Open items

- The **scheduled run and the tag-based selection were never exercised**. An optional extension: set the schedule a bit ahead and check which jobs appear (AWS gives a start window of at least an hour)
- The restore metadata did not show a volume type, so a production restore should state size, type and encryption explicitly
- Azure phase: repeat the backup lab with an Azure Backup vault, a policy and a protected VM, and verify that the first scheduled backup really protects the VM
- **Day 6:** Ansible on Windows over WinRM
- Housekeeping: update the root `README.md` (PowerShell and AWS Backup as Done) and `docs/notes-and-lessons.md`, check `git status` for `terraform.tfvars` and `ansible/inventory.ini`, then commit
