# Day 4 — Session Review (step by step)

A chronological review of the whole Day 4 session: preparation, learning, lab, review questions, the follow-up discussion on production backups, and the documents produced. For the full command list of the lab, see `steps-summary.md` in the same folder.

**Status reminder:** everything in this session is **lab work**. It is self-directed practice in a personal AWS account, not production experience.

---

## 1. Preparation

1. **Confirmed nothing was still running** from Day 3 (empty list of running instances).
2. **Recreated the bucket variable** (`$bucket`) for the S3 state backend from Day 3.
3. **Checked current AWS pricing** for snapshots and AMI details before starting.

---

## 2. Learning block

Topics covered before touching the lab:

- **EBS snapshots:** point-in-time copies of a volume, incremental, regional, billed by stored data, independent of the instance and volume they came from
- **Two restore paths:** snapshot → volume → attach (a disk), and snapshot → AMI → launch (a whole server)
- **Crash-consistent vs. application-consistent** backups, and VSS on Windows
- **RPO and RTO**
- **The orphaned-snapshot cost trap:** snapshots survive `terraform destroy` if created outside Terraform
- **Azure parallels:** managed disk snapshot, image, Azure Backup

---

## 3. Lab, step by step

| # | Step | Key result |
|---|---|---|
| 1 | Created `06-aws/day4-snapshots-restore`, one folder at a time | Project folder ready |
| 2 | Wrote `main.tf`: S3 backend (new state key), security group, Linux instance, 2 GB data volume, volume attachment, outputs | Every block commented |
| 3 | `init`, `fmt`, `validate`, `plan`, `apply` | Four resources created |
| 4 | Found the new disk with `lsblk`, ran `mkfs`, mounted it at `/data`, wrote `file1.txt`, ran `sync` | `mkfs` run once, on a new empty disk only |
| 5 | Snapshot #1 **via the CLI**, waited for completion | Terraform does not know about it |
| 6 | Wrote `file2.txt`, added `aws_ebs_snapshot` to `main.tf`, applied (snapshot #2 **via Terraform**) | CLI snapshot holds `file1.txt` only, Terraform snapshot holds both |
| 7 | **Simulated the disaster** with `terraform destroy` | Terraform's snapshot was destroyed with the project. The CLI snapshot survived |
| 8 | Removed the snapshot resource, added `snapshot_id` to the volume, applied | Everything rebuilt fresh, volume restored from the snapshot |
| 9 | Mounted the restored volume **without** `mkfs` | `file1.txt` present, `file2.txt` absent: point-in-time proven |
| 10 | *Optional bonus:* created an AMI, then deregistered it **before** deleting its snapshot | Order matters (see section 4). Remove this row from your notes if you skipped it |
| 11 | Final `destroy`, deleted the CLI snapshot, ran four verification checks | Snapshots, volumes, images and running instances all empty |

Cleanup rule confirmed again: the S3 state bucket from Day 3 stays, everything else is removed.

---

## 4. Review questions and corrections

| # | Topic | Result |
|---|---|---|
| 1 | Why the CLI snapshot survived destroy | Correct. Nuance added: tracking everything under Terraform is right for **cost hygiene**, but **backups need a different lifecycle** from what they protect |
| 2 | Crash-consistent vs. application-consistent | Correct. Crash-consistent means "as if the power was cut". VSS is the Windows answer |
| 3 | Why `file2.txt` was missing, why not to run `mkfs` | Correct. The restore used the CLI snapshot, taken before `file2.txt` existed |
| 4 | Snapshot vs. AMI restore, deregister order | **Needed precision:** an EBS snapshot is a copy of a **volume**, not an instance, so restoring gives a disk. An AMI is a template built on snapshots. AWS refuses to delete a snapshot that backs a registered AMI, so deregister first, and deregistering alone leaves the snapshot billed |
| 5 | RPO and RTO | RPO correct. **RTO refined:** it is a **target** (maximum acceptable downtime) set with the business, compared against the **measured** restore time from a test |

**Correction from my side:** I first said "almost nobody" creates snapshots in Terraform. That was too strong. They are used for one-offs (a snapshot before a risky change, seeding volumes), but they are rare as a backup **strategy**.

---

## 5. Follow-up discussion

### 5.1 Should the workload and its backups be in the same Terraform project?

Not with the same lifecycle. The distinction is between backup **policy** and backup **data**:

- **Policy** (what, how often, how long) is Terraform code, in its own project and state
- **Data** (recovery points) lives in a vault, outside the workload's lifecycle, ideally locked and copied to another region or account
- **Workloads** opt in, for example with a tag such as `backup = daily`
- `prevent_destroy` is a safety net only while the resource block exists in the code, so it does not replace separate lifecycles

### 5.2 What a snapshot contains and does not contain

- A snapshot is **storage only**. A restored data volume gives the data, and a restored root volume needs an AMI or a root-volume swap to become a bootable machine
- **Not included:** instance type, security groups, key pair, IAM role, tags, memory, running processes, instance store volumes, and anything written after the snapshot
- Mental model: **machine = configuration + disks.** Terraform recreates the configuration, snapshots recreate the data
- Windows gotchas: domain trust after restoring an old snapshot, and domain controllers needing AD-aware recovery

### 5.3 What is real and what is lab-only

- **Real:** Terraform building EC2, EBS and security groups, remote state with locking, tags, volumes from `snapshot_id`, and a CLI snapshot before a risky change
- **Lab-only:** workload and backups in one project, `destroy` as the "disaster", manual formatting over SSH, one person with full admin rights, no review pipeline

### 5.4 How a real admin plans this work

Four layers with owners: **foundation** (network, IAM, state, backup vault and plans), **workloads**, **configuration** (Ansible, GPO, Intune), and **operations** (monitoring, patching, restore tests). A request such as "a Windows server with a data disk, backed up daily" goes through:

1. Clarify requirements (RPO, RTO, retention, owner, budget)
2. Check what already exists
3. Design the workload to **consume** the backup standard (a tag), not define backups itself
4. Build in dev on a branch, with the `plan` reviewed in a pull request
5. Configure through automation, not by hand
6. **Test a restore**
7. Promote to production through the pipeline, with an approval gate
8. Document, and alert on **backup job failures**
9. Repeat restore tests and cost and orphan checks over time

### 5.5 How to explain this lab in an interview

Four parts: **goal, what I built, what I learned, how production differs.** The strongest point is the lifecycle discovery: the snapshot Terraform managed was destroyed with the project, while the manual one survived, which shows that a backup should not share a lifecycle with its source. Do not claim production experience. For "that's not how we do it", answer that the single project was a deliberate learning choice, then describe the production layers.

---

## 6. Documents produced in this session

| File | Where to put it | Purpose |
|---|---|---|
| `day4-aws-steps.md` | `06-aws/day4-snapshots-restore/steps-summary.md` | Command-level steps of the lab |
| `day4-aws-review-qa.md` | `06-aws/day4-snapshots-restore/review-qa.md` | Review answers plus the extended notes (production design, snapshot contents, lab vs. production, interview framing) |
| `aws-azure-mapping.md` | `docs/aws-azure-mapping.md` | Concept mapping with the backup, snapshot and restore scenarios, and the whole-week lab vs. production table |
| `day4-session-review.md` | `06-aws/day4-snapshots-restore/session-review.md` | This chronological review |

---

## 7. Key lessons from the day

- A snapshot copies a **volume**, not an instance. Machine = configuration + disks
- Restores are **point-in-time**: nothing written after the snapshot comes back
- Never run `mkfs` on a restored volume. It erases the data
- A backup that shares a lifecycle with its source disappears with it
- Anything created outside Terraform keeps costing money until it is deleted by hand
- Deregister an AMI **before** deleting its snapshot, and delete the snapshot too, or it keeps being billed
- An untested backup is not a backup: measure restore time against the RTO
- Know the difference between the lab and production, and say it plainly in an interview

---

## 8. Open items and next steps

- **Scenario 6 (production-style managed backup) is not practiced on either cloud yet.** It is the priority backup lab for the Azure phase, and optionally a short AWS Backup lab beforehand
- The Azure column of `aws-azure-mapping.md` is **plan and knowledge only**. Items marked *verify* must be checked when practicing
- Update the root `README.md` (add Day 4 and the mapping file) and `docs/notes-and-lessons.md` (add the lessons above)
- Commit:
  ```powershell
  cd ~/infra-learning-lab
  git status
  git add .
  git commit -m "Day 4 AWS: session review, extended backup notes, AWS-Azure mapping"
  git push
  ```
- Before the commit, check that the Terraform files contain placeholders instead of the bucket name, your IP, the key pair name, and the snapshot ID
