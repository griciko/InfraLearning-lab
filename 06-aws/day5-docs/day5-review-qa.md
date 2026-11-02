# Day 5 — Review Q&A

Review notes for Day 5: exit codes and CI credentials, the AWS Backup lab (separate platform and workload projects), and the timed restore.

**Lab vs. production:** all of this is lab work. The production notes say where real environments differ.

---

## A. PowerShell and CI

### A1. What does "using exit codes to flag leftovers" mean?

An exit code is the number a program returns when it finishes, and the system or the next tool can read it. 0 means "finished, nothing wrong" and anything else means "something to look at". A pipeline can't read a script's printed output to judge it, it only sees the exit code: 0 turns the step green, anything else fails the step and marks the run red. The script uses three codes: 0 = clean, 1 = leftovers found, 2 = pre-flight or a check failed (the checker itself is broken). GitHub only distinguishes green from red, but the three codes let a person or another script tell "something is costing money" apart from "the checker is broken". The same mechanism explains why `terraform fmt -check` turned a pipeline red in Week 1, and tools like robocopy define their own meaning for their codes.

### A2. Why is a stored admin key in GitHub a weak setup, and what was done?

Secret masking only hides the value in logs, any workflow step can still read the secret. What actually protects it is who can change workflows and what the credential is allowed to do. The leftovers script only needs `describe` calls, so the stored credential was replaced with a dedicated **read-only IAM user** (least privilege). Production pipelines avoid long-lived keys entirely, using short-lived credentials via OIDC federation.

---

## B. AWS Backup lab

### B1. Why are the platform and the workload separate Terraform projects, and what is the only backup-related thing in the workload code?

The volume is created in the **workload** project, and it is also attached there. The platform project never touches a volume: it holds the vault, the role, two policy attachments, the plan and the selection, in other words backup policy and storage location. The two projects share no resource and are linked only by the **tag** `backup = daily`: the workload tags its data volume, and the platform's selection backs up everything with that tag. That tag is the only backup-related thing in the workload. They are separate because they have different lifecycles (the workload is destroyed often, backups must outlive it), different owners in production, and different state files, so a destroy or a mistake in one can't remove the other.

### B2. What do the two parts of the backup role decide?

The **trust policy** decides *who* may assume the role (the AWS Backup service). The **attached policies** decide *what* it may do once assumed. Analogy: who may log on as a service account vs. the permissions that account has.

### B3. Why can the Ansible filesystem task run safely on a disk that already has a filesystem, and why build the device path from the volume ID?

The filesystem task describes a result ("this device should have XFS") and checks first: if XFS is already there it reports `ok` and changes nothing, and if a different filesystem is there it fails by default unless `force: true` is set. A manual `mkfs` never checks and always erases, which is why it must never be run on a restored volume. The task order matters: check the device (stat, assert), create the filesystem, create the mount directory, mount (and record in `/etc/fstab`), write the test file once, then `sync`. The device path comes from the EBS volume ID because NVMe names like `nvme1n1` are assigned in enumeration order and are not a fixed identity, so a guessed name could point at the wrong disk. AWS recommends identifying devices by volume ID. Windows has the same idea: identify a disk by its unique ID or serial number instead of "Disk 1".

### B4. After the workload was destroyed, why did the recovery point survive, and why was `force_destroy` left unset?

The recovery point lives in the **vault**, which belongs to the platform project and a different state, so the workload's `destroy` only removed what was in the workload's state. `force_destroy` would delete **all recovery points in the vault** whenever the vault is destroyed. Left unset, Terraform refuses to destroy a vault that still holds recovery points, which protects against deleting backups by accident, so in the cleanup the recovery points are removed as a deliberate step.

### B5. Which part did the on-demand job not test?

On-demand and scheduled backups start differently. The on-demand job used the vault and role directly against one resource ARN. A scheduled run uses the plan's schedule, and AWS Backup finds the resources through the **selection**: everything tagged `backup = daily`. So today's job tested the vault, the role's permissions and the backup itself, but **not** the schedule or whether the volume's tag really matches the selection. Tags are case-sensitive, so a mismatch such as `Backup = Daily` would mean the plan quietly protects nothing, discovered only when a restore is needed. Production teams check that the first scheduled run really produced recovery points and alert on missing or failed backups.

---

## C. Restore

### C1. Why was the restore verified with a separate read-only playbook?

The first playbook writes the test file, and with `force: false` it would **create it if it were missing**. After a failed restore it would quietly recreate `file1.txt` and the check would still pass. The verify playbook never writes data, and it also fails if the restored disk has no XFS filesystem instead of formatting it. The goal of the check is to see the file that came from the backup, so the check must not be able to produce that file itself.

### C2. Why is the restore job's time only part of the recovery time?

The measured recovery was: restore job 01:58, rebuild 08:37, verification 02:26, total 13:02. The restore job is one phase. Rebuilding the infrastructure and verifying the data are part of the downtime too, and in a real incident so are noticing the failure, deciding, approvals, and finding the right recovery point. In this lab the rebuild and verification times include the author's own typing (editing Terraform files, writing the playbook). With prepared code, playbooks and procedures, and almost no manual work, those phases shrink to mostly machine time, which is why teams prepare runbooks and automation in advance and repeat restore tests. The RTO is a **target** set with the business before the infrastructure is built, and the measured total is compared against it.

### C3. What does an 11-hour recovery point age mean for a business that can lose at most 4 hours?

RPO is the **maximum** acceptable data loss, judged on the worst case: the failure happens just before the next backup, and everything since the last one is lost. The backup interval therefore must be **at most the RPO**, not twice it. An 8-hour interval has a worst case of 8 hours and an average of about 4, so it fails a 4-hour RPO. A 4-hour interval only just meets it, and in practice you go tighter (for example 2 hours), because one failed backup doubles the gap, and you alert on failed backup jobs. The change is the `schedule` in the backup plan. The 11:37 measured in the lab came from the break between two sittings, not from a schedule. With a once-a-day plan the worst case is about 24 hours.

### C4. Who deleted the restored volume?

The restored volume was created by the restore job, outside Terraform, so it was never in Terraform's state (`count = 0` on the new-volume resource, and the attachment only detaches). Terraform doesn't remove what it didn't create. CloudTrail showed that the `DeleteVolume` call came from **`aws-cli`** with the command `ec2.delete-volume`, so it was the manual delete in the cleanup, not Terraform. The leftovers script run right after the destroy listed the restored volume as unattached, next to the snapshot, exactly the leftover the lab predicted, and the volume was then deleted by hand with the CLI. (The first review answer, "deleted by Terraform", was a mix-up with that manual delete.) Two takeaways: a restore job's output is a leftover to adopt (import) or delete, and the audit trail identifies **which tool** made each call, so when something disappears, check CloudTrail instead of arguing about it.

---

## D. Lab vs. production: the backup lab

| Topic | In the lab | In production |
|---|---|---|
| Vault | Default settings | KMS-encrypted, vault lock, copies to another region or account, notifications on failed jobs |
| IAM | Managed policies on one role | Least privilege, reviewed role design |
| Backup start | One on-demand job | Scheduled plans, with the first scheduled run checked |
| Restore | By hand, same account, one recovery point | Into an isolated environment first, automated verification |
| Restored resources | Deleted by hand | Imported into the IaC or replaced with a Terraform-built volume |
| Restore test | Once, timed | Scheduled, logged, compared with the RTO and RPO |
| Alerts | None on backup jobs | Alerts on failed or missing backups |
| Audit | CloudTrail checked once | Central, retained, monitored |

---

*Day 5 covered: exit codes and least-privilege CI credentials, separate platform and workload Terraform projects linked by a tag, an IAM service role (trust vs. permissions), idempotent disk preparation by Ansible using stable device IDs, an on-demand backup, a backup that outlives its source, a restore into rebuilt infrastructure, read-only verification, RPO/RTO reasoning with measured numbers, and an audit-trail check of who deleted a resource.*
