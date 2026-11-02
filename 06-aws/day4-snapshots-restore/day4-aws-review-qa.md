# AWS — Day 4: Review Q&A

Notes from the review session after the snapshot, backup and restore lab: an instance with a data volume, snapshots taken via the CLI and via Terraform, a simulated disaster, a restore, and an optional AMI step.

---

### 1. After `terraform destroy`, the CLI snapshot survived but the Terraform-managed one was destroyed. Why, and what does that say about where a backup should live?

Terraform only manages what is in its state, so everything it created is destroyed by it, and anything created by hand (the CLI snapshot) is outside it and must be deleted manually through the CLI or the console. For cost hygiene it is better to keep everything under one tool, so nothing untracked is left behind and quietly billed. Backups are the exception to that rule. The Terraform-managed snapshot lived in the same project as the volume it protected, so `destroy` removed both, and a backup that dies together with its source does not protect against that failure. Real setups give backups a different lifecycle: a separate project and state, `lifecycle { prevent_destroy = true }` on the backup resource, or a managed service such as AWS Backup with copies in another region or account. Two rules: track everything for cost, and never let backups share the fate of what they protect.

---

### 2. Why is a snapshot of a running instance only crash-consistent, and how would you get an application-consistent copy on Windows?

A snapshot of a running instance captures the disk as it is at that moment, equivalent to the power being cut. The filesystem usually recovers, but data still in use, such as a database with half-written transactions, can be inconsistent. For an application-consistent copy, stop the applications or stop the instance before taking the snapshot. On Windows, VSS (Volume Shadow Copy Service) allows consistent backups even of a running server. AWS also has VSS-based tooling for this (via AWS Backup and Systems Manager), but the exact mechanism should be checked in the current documentation.

---

### 3. Why was there no `file2.txt` on the restored volume, and why was it important not to run `mkfs` on it?

The restore used the CLI snapshot, which was taken before `file2.txt` was written (the Terraform snapshot, taken afterwards, contained both files). That is what point-in-time means: the restored volume reflects the moment of the snapshot, nothing later. The restored volume already contained a filesystem and the data, so creating a filesystem was unnecessary. Running `mkfs` again would have destroyed the files and created a new empty filesystem.

---

### 4. What's the difference between restoring from a snapshot and from an AMI, and why did the order "deregister the AMI, then delete its snapshot" matter?

An EBS snapshot is a copy of a **volume**, not of an instance. Restoring one gives a disk, which is attached to an instance, as was done with the data volume. To get a complete bootable server back, the root volume is snapshotted, turned into an AMI, and launched. An AMI is a template, not an instance itself, and it can launch many instances. It is built on top of snapshots: it points to the snapshot(s) of the volume(s) and adds launch settings.

The order matters for two reasons. AWS refuses to delete a snapshot that backs a registered AMI, so the AMI must be deregistered first. And deregistering alone does not delete the snapshot, which keeps being billed until it is deleted explicitly. Both steps are needed, in that order.

---

### 5. What are RPO and RTO, and how does RPO decide how often to take snapshots?

Both are decided with the business before the infrastructure is built, with the admin giving input on what is feasible. **RPO (Recovery Point Objective)** is the maximum amount of data loss that is tolerated. If too much data changes between weekly full backups, the RPO is not met, so the schedule is tightened, for example to every 2-3 days with incrementals in between, or more often. **RTO (Recovery Time Objective)** is the maximum acceptable downtime, a target. Testing a restore measures the actual restore time, which is compared against the RTO. If the actual time is longer, the design is changed (more frequent fulls, faster storage, a standby).

With traditional backup software, a full backup plus a chain of incrementals lengthens a restore, because the chain has to be applied. EBS snapshots hide this: each snapshot restores as a complete volume and AWS manages the chain. A volume restored from a snapshot does load its data lazily, so first reads can be slower, which matters for RTO. AWS has a paid feature (Fast Snapshot Restore) for that, noted as awareness only.

---

## Extended notes: backups in production vs. the lab

Added after the review, to separate what this lab did from how backups are built in production. **Everything in Day 4 is lab work.** The building blocks are real, but the way they were combined (one project, one person, manual steps) is a simplification for learning.

### 6. Should the workload and its backups live in the same Terraform project?

Not with the same lifecycle. The useful distinction is between backup **policy** and backup **data**:

- **Policy** (what is backed up, how often, how long it is kept) can and should be Terraform code.
- **Data** (the recovery points themselves) must not depend on the workload's `destroy`.

The `aws_ebs_snapshot` resource used in the lab was a learning device. It does have real uses, such as a one-off snapshot before a risky change or seeding volumes, but as a backup strategy it is rare. In production a service takes snapshots on a schedule (AWS Backup or Data Lifecycle Manager), and Terraform defines only the schedule.

**Typical layout:**

```
platform-backup/      own project and state, owned by the platform/infra team
  vault, backup plans, IAM role, copy rules to a second region or account

workload-app1/        own project and state, owned by the app/infra team
  EC2 + EBS, tagged  backup = "daily"
```

**Trimmed illustration of the backup side** (not part of the lab, the IAM role it needs is omitted):

```hcl
# Vault: where the recovery points are stored
resource "aws_backup_vault" "main" {
  name = "main-vault"
}

# Plan: the schedule and how long each backup is kept
resource "aws_backup_plan" "daily" {
  name = "daily-35-days"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 * * ? *)" # every day at 03:00 UTC

    lifecycle {
      delete_after = 35 # days
    }
  }
}

# Selection: which resources are covered, chosen by TAG rather than by name
resource "aws_backup_selection" "tagged" {
  name         = "tagged-resources"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn # role defined elsewhere

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup"
    value = "daily"
  }
}
```

On the workload side, the only change is a tag on the instance: `tags = { backup = "daily" }`.

**Why this design works:**

- **Independent lifecycles:** destroying and rebuilding the workload does not touch the backups, because they live in the vault and the workload's state doesn't know about them.
- **Enforcement by tag:** a new server is backed up just by carrying the tag, with no edit to the backup project.
- **Protection:** the vault can be locked against deletion, and copies can go to another region or account, so one mistake or one compromised account can't erase everything.
- **Recovery:** restoring means running the workload project again with the recovery point as input, the same idea as `snapshot_id` in Step 8.

`lifecycle { prevent_destroy = true }` is a useful safety net, but it only protects while the resource block exists in the code. If the block is removed, nothing protects it, which is the Week 1 lesson again. It does not replace separate lifecycles.

**Azure parallel:** Azure Backup with a Recovery Services vault and backup policies assigned to VMs follows the same separation of policy and data (see `docs/aws-azure-mapping.md`).

---

### 7. What a snapshot contains and what it does not

A snapshot is storage only: a copy of a **volume**, not of an instance.

| Restored | What you get back |
|---|---|
| **Data volume** | The data. Attach it to any new instance and mount it (what the lab did) |
| **Root volume** | The OS, software and settings. It can't simply be attached as an extra disk and booted: turn it into an AMI, or swap it in as the root volume of a stopped instance (AWS also has a replace-root-volume feature, check the docs) |

**Not in a snapshot**, so a restored machine is similar but not identical:

- The instance configuration: type, security groups, key pair, IAM role, subnet, tags, user data
- Identity: a new instance ID, and the public IP changes
- Memory and running processes (a snapshot is disk only, so the machine starts as after a power loss)
- Instance store volumes
- Anything written after the snapshot

Mental model: **machine = configuration + disks.** Terraform code recreates the configuration, and snapshots recreate the data. That is exactly what Day 4 did.

**Windows-specific gotchas:** a domain-joined server restored from an old snapshot can have an outdated machine account password, which may break its trust with the domain. Domain controllers need AD-aware backup and recovery rather than raw disk copies, because restoring one risks USN rollback.

---

### 8. Lab vs. production: Day 4 activities

| Activity | In the lab | In production |
|---|---|---|
| Building EC2, EBS, security group with Terraform | Done by hand from a laptop | Same building blocks, but through pull requests and a pipeline |
| Remote state in S3 with locking | Done | Done, plus strict access control |
| Tags on resources | Used for names | Essential: they drive backups, cost reports and ownership |
| Volume created from `snapshot_id` | Used to restore | Used for recovery, cloning, and DR rebuilds |
| CLI snapshot before a change | Used as the backup | A common one-off before a risky change |
| `aws_ebs_snapshot` as the backup | Used to learn how Terraform tracks it | Rare as a strategy. A service runs scheduled backups |
| Workload and backup in one project | Done, which exposed the lifecycle problem | Never: separate projects, separate states |
| `terraform destroy` as the "disaster" | Simulated | Real disasters are accidental deletion, corruption, ransomware, an outage |
| Formatting and mounting the disk over SSH | Done by hand | Automated with Ansible or user data, so it is repeatable |
| One person, full admin rights, no review | Yes | Least privilege, reviewed changes, approval gates |
| Restore | Done once, successfully | Tested regularly on a schedule, with the time measured against the RTO |
| Alerting | Raw SNS email on instance state | Alerts on **backup job failures**, in structured dashboards with on-call |

---

### 9. How to explain this lab in an interview

Use four parts: **goal, what I built, what I learned, how production differs.**

> "I built a lab to understand how Terraform interacts with storage and backups. I provisioned an instance with a data volume, took snapshots both manually and through Terraform, destroyed everything, and restored from a snapshot. The useful discovery was lifecycle: the snapshot Terraform managed was destroyed with the project, while the manual one survived. That showed me a backup shouldn't share a lifecycle with its source. In production I'd keep the backup policy in a separate project, use AWS Backup with tag-based selection, lock the vault, copy to another region or account, and test restores regularly."

**Likely follow-ups:**

- *"That's not how we do it."* "Right. I kept it in one project on purpose, to see the mechanics and hit the lifecycle problem myself. Here is how I'd structure it in production," then describe the layers (foundation, workloads, configuration, operations).
- *"Why use Terraform for snapshots?"* "To see how Terraform tracks resources and what happens to backups on destroy, not as a backup strategy."
- *"Have you done this in production?"* "No, this is self-directed lab work. I've applied production habits to it: remote state with locking, reading the plan before every apply, and verifying a clean teardown."

Don't claim more than the lab. The strongest part is that the lifecycle issue was found and explained independently. Also connect it to existing work: map the lab to how Windows server backup and restore is done today (backup software, VSS, snapshots), because that link is stronger than any cloud-only answer.

---

*Lab covered: an EBS data volume attached with Terraform, formatting and mounting, snapshots via the CLI and via `aws_ebs_snapshot`, the difference in lifecycle between them, a simulated disaster and restore with one added line of code, point-in-time behavior, crash-consistent vs. application-consistent backups, AMIs and their snapshots, RPO and RTO, and a four-point verification of a clean teardown.*
