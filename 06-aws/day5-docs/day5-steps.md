# Day 5 — Steps Summary

Wrap-up, a PowerShell script for AWS leftovers, and a production-style backup lab (AWS Backup) with a timed restore. Region: `eu-north-1`.

**Lab vs. production:** everything here is lab work in a personal AWS account. Each part notes where production differs.

| Part | Content |
|---|---|
| 1 | Wrap-up: README, notes, repo check for personal data |
| 2 | PowerShell: `check-aws-leftovers.ps1`, plus a GitHub Actions workflow that runs it |
| 3 | AWS Backup lab: separate platform and workload projects, Ansible, backup, restore, RTO measurement, cleanup |

---

## Part 1 — Wrap-up

1. **Updated the root `README.md`:** status table for all topics, a lab-vs-production banner near the top, the lab environment list, and the AWS work under "What I built".
2. **Extended `docs/notes-and-lessons.md`** with the lessons of the AWS week (Days 1-4) and cross-topic rules.
3. **Searched the repo for personal data**, in current files and in history: account ID, public IP, email, bucket name, `AKIA`, `PRIVATE KEY`, key names, plus tracked state, key, `.tfvars` and inventory files.
4. **Findings** (repo is private, still sanitized): a tracked `04-ansible/inventory.ini` (the Week 1 localhost file), the public IP in Day 1-2 `main.tf`, and key pair or file names in Day 1-3 `main.tf`.
5. **Decision:** move the IP and key names into variables, with real values in `terraform.tfvars` (Git-ignored) and placeholders in `example.tfvars`. From the Azure phase on, use the standard layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `terraform.tfvars`, `example.tfvars`. Recommended rule: ignore generated inventories with `06-aws/**/inventory.ini` in `.gitignore`.

---

## Part 2 — PowerShell: `check-aws-leftovers.ps1`

A **read-only** script that lists AWS resources which keep costing money after a lab session.

6. **Created `05-powershell/scripts/check-aws-leftovers.ps1`**, built in five blocks:
   - `param()` with the region (default `eu-north-1`) and `$ErrorActionPreference = "Stop"`
   - Two functions: `Invoke-AwsJson` (runs the CLI, checks `$LASTEXITCODE`, converts JSON to objects) and `Test-AwsReady` (CLI present, credentials work, account ID masked except the last 4 digits)
   - A list of five checks as hashtables: EC2 instances (including stopped), unattached volumes, snapshots owned by the account, AMIs owned by the account, unattached Elastic IPs
   - Pre-flight in `try/catch`, then a `foreach` loop over the checks with per-check error handling
   - A summary with exit codes: **0** clean, **1** leftovers found, **2** pre-flight or a check failed
7. **Tested it:** a clean run, a deliberate leftover (a 1 GB volume, caught and then deleted), and the failure path with an invalid region.
8. **Execution policy:** checked with `Get-ExecutionPolicy -List`. If local scripts are blocked, `RemoteSigned` for the current user is enough for scripts created locally.
9. **Practiced `Get-Help` and `Get-Command`** to find answers without a web search.
10. **Documented the script** in `05-powershell/README.md`, including the lab-vs-production note.

### Extra: running the script from GitHub Actions

11. **Created a workflow** that runs the script manually and on a schedule, using `shell: pwsh` and AWS credentials from repository secrets. The run went green.
12. **Exit codes explained:** an exit code is the number a program returns when it finishes. 0 means success and anything else means "look at this". A pipeline can't read the script's printed output to judge it, it only sees the exit code, so exit code 1 turns into a red run.
13. **Replaced the stored credentials with a read-only IAM user** (`github-readonly-checker`, a read-only EC2 policy), because a job that only reads should only be able to read. Optional proof: `aws ec2 create-volume --dry-run` with the read-only profile fails with `UnauthorizedOperation`.
14. **Lab vs. production:** stored access keys are a lab shortcut. Production pipelines get short-lived credentials through OIDC federation, so there is no key to steal or rotate. Planned for when CI/CD and the cloud work are combined.

---

## Part 3 — AWS Backup lab

Two **separate** Terraform projects with separate state, linked only by a tag (`backup = daily`).

### 3.1 Platform project (`06-aws/day5-backup-platform`)

15. **Files:** `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`. State in the Day 3 S3 bucket under its own key.
16. **Six resources:** backup vault, IAM role for AWS Backup, two managed policy attachments (backup and restore), backup plan (daily 03:00 UTC, retention from a variable), tag-based backup selection.
17. **The role has two parts:** a **trust policy** (who may assume it: the AWS Backup service) and **attached policies** (what it may do). The selection depends on the attachments, because a new role can be briefly rejected while IAM propagates.
18. **`force_destroy` left unset on purpose**, so a vault holding recovery points can't be deleted by accident.
19. **Verified** with the CLI: the vault exists, and the selection holds the tag condition.

### 3.2 Workload project (`06-aws/day5-backup-workload`)

20. **Files:** the same layout plus `terraform.tfvars` (real values, ignored) and `example.tfvars` (placeholders). Variables: region, my IP, key pair name, SSH key path, backup tag value.
21. **Five resources:** security group (SSH from my IP), Linux instance, 2 GB data volume, volume attachment, generated Ansible inventory.
22. **The only backup-related thing in the workload is the tag on the data volume.** The workload never mentions vaults or plans. Only the volume is tagged, so the root volume isn't backed up.

### 3.3 Ansible prepares the data disk

23. **Playbook `ansible/prepare-data-disk.yml`:** stat and assert that the device exists, create XFS only if no filesystem exists, create `/data`, mount it (with `nofail` in `/etc/fstab`), write a test file once (`force: false`), and `sync`.
24. **The device path is built from the EBS volume ID** (`/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<volume id without hyphen>`), not from a guessed `nvme1n1`, because NVMe device names depend on enumeration order and are not a fixed identity.
25. **Ran it twice:** the first run changed things, the second reported no changes (idempotency on a real disk, and it can never reformat a disk that already has a filesystem).

### 3.4 On-demand backup

26. **Started a backup job** against the vault and role with `aws backup start-backup-job`, with `DeleteAfterDays=7` as a safety net. Polled the job state with a PowerShell `do/while` loop. It completed in 1-2 minutes, and the recovery point was 68.5 MB (the written blocks, including the filesystem metadata, not the 2 GB volume size).
27. **The leftovers script listed the snapshot** behind the recovery point, which is expected.
28. **What this did not test:** the tag-based selection and the schedule. The job was on-demand against the vault and role directly. Only a scheduled run proves that the volume's tag matches the selection (tags are case-sensitive).

### 3.5 Backups survive a destroy

29. **Destroyed only the workload project.** The plan listed the instance, volume, attachment, security group and inventory, and nothing of the vault or plan. Afterwards the volume was gone, and **the recovery point was still in the vault**.

### 3.6 Restore

30. **Fetched the restore metadata** with `aws backup get-recovery-point-restore-metadata`. It contained encryption, volume ID and size, a request ID, and **an empty availability zone**. It did not show a volume type.
31. **Chose the AZ with a fallback:** the original AZ if present, otherwise the first AZ offering `t3.micro`. Set it in the metadata and saved it as JSON in a temp folder outside the repo.
32. **Started the timer** (`Stopwatch`) and the restore job (`start-restore-job`, with the copy-source-tags option so the restored volume gets its `Name` tag). Waited on `Status` (restore jobs use `Status`, backup jobs use `State`). Took the new volume ID from the job's created-resource ARN.

### 3.7 Rebuild with the restored volume

33. **Updated the workload code:** two new variables (`availability_zone`, `restored_volume_id`), a `locals` block deciding restore or create, `count` on the new-volume resource, the attachment and inventory using the chosen volume ID, and the instance pinned to the AZ.
34. **Read the plan before applying:** 4 resources (security group, instance, attachment, inventory) and **no new volume**.

### 3.8 Verification with a read-only playbook

35. **Playbook `ansible/verify-restore.yml`:** checks the device, reads the filesystem type with `blkid` and fails if it isn't XFS (never formats), mounts, asserts that `file1.txt` exists, and prints it. It never writes data, so a failed restore can't be hidden (the first playbook would recreate a missing file).
36. **Result:** the original file came back with its original timestamp.

### 3.9 Measured restore (against a self-defined RTO)

| Phase | Time | Note |
|---|---|---|
| Restore job | 01:58 | AWS doing the work |
| Rebuild (apply) | 08:37 | Includes editing the Terraform files |
| Verification | 02:26 | Includes creating the playbook |
| **Total** | **13:02** | Compare with the RTO written down in advance |
| Recovery point age | 11:37:35 | The data loss for this test (compare with an RPO) |

The rebuild and verification times include typing time. With prepared code and playbooks they would be mostly machine time.

### 3.10 Cleanup (leftovers script before and after)

37. **Baseline:** 1 instance and 1 snapshot (exit code 1).
38. **Destroyed the workload** (the restored volume is not in its state). **The leftovers script after the destroy listed one unattached volume and the snapshot:** the restored volume had survived, because Terraform never created it.
39. **Deleted the restored volume by hand** with `aws ec2 delete-volume`. **CloudTrail confirmed** that the delete came from `aws-cli` (`ec2.delete-volume`) and not from Terraform. Terraform doesn't remove what it didn't create, so a restore job's volume is a leftover to adopt or delete.
40. **Deleted the recovery point through AWS Backup** (which also removes the snapshot behind it), waited until the vault was empty, then **destroyed the platform project** (6 resources).
41. **Final check:** `none found` for all checks, exit code 0. The temporary metadata file was removed, and the state files in the S3 bucket stay.

---

*Result: a production-style backup design practiced end to end in a lab: policy separated from workload, tag-based opt-in, a backup that outlives its source, a restore into rebuilt infrastructure verified without any chance of masking a failure, a measured recovery time, and a verified clean teardown. The scheduled run and the tag selection remain untested.*
