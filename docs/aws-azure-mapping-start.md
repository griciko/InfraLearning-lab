# AWS ↔ Azure Mapping

Planning document for the Azure phase. Built during the AWS lab week and updated as each Azure lab is completed.

---

## How to read this document

**Status of each column**

- **AWS column:** hands-on, done in my lab (`06-aws/`).
- **Azure column:** knowledge and plan only, **not yet practiced**. Items marked *verify* must be checked against current Microsoft documentation and provider docs when I reach that lab.

**Mapping legend**

| Label | Meaning |
|---|---|
| **Maps directly** | Same concept, similar workflow |
| **Maps loosely** | Same goal, different model or structure |
| **AWS-only / Azure-only** | No real equivalent on the other side |

**Lab vs. production: read this first.** Everything I built is **lab work**: one person, full admin rights, one project per exercise, manual steps, no review pipeline. I use it to learn the mechanics and to hit real failure modes safely. It is not production experience. Wherever production differs, the sections below say so under "Production note", because understanding that difference matters as much as the commands.

---

## 1. Core services

| Area | AWS (done in lab) | Azure (planned) | Mapping | Notes |
|---|---|---|---|---|
| Virtual machine | EC2 instance | Azure VM | Maps directly | Same Terraform and Ansible concepts |
| Instance size | Instance type (`t3.micro`) | VM size (`Standard_B...`) | Maps directly | Availability and quotas differ per region and subscription |
| OS template | AMI | Managed image / Azure Compute Gallery image | Maps loosely | See section 2 |
| Virtual network | VPC and subnet (default VPC used) | VNet and subnet | Maps directly | Production uses dedicated networks, not defaults |
| Firewall rules | Security group (allow rules only, attached to instance) | Network Security Group (priorities, allow and deny, attached to subnet or NIC) | Maps loosely | Same purpose, different rule model |
| Remote login (Linux) | Key pair, SSH | SSH public key on the VM | Maps directly | |
| Remote login (Windows) | AWS encrypts a generated password with the key pair's public half, decrypted with the private `.pem` (RSA only) | Admin username and password are set when the VM is created | Maps loosely | No decryption step in Azure |
| Fixed public IP | Elastic IP | Static public IP | Maps directly | AWS dynamic IPs change on stop/start. Azure dynamic IPs behave similarly, *verify* |
| Stopped state and billing | Stopped = no compute billing, EBS storage still billed | Stopped (deallocated) = no compute billing. Stopped from inside the OS = still allocated and billed | Maps loosely | Important cost difference, *verify* when practicing |
| Object storage | S3 | Blob Storage | Maps directly | |
| Identity and access | IAM users, roles, policies | Entra ID + Azure RBAC | Maps loosely | Entra is identity-first, IAM is policy-first |
| CLI | `aws` | `az` | Maps directly | Authentication: access keys vs `az login` |
| Terraform provider | `aws` | `azurerm` (+ `azuread` for Entra ID) | Maps directly | Intune uses a Graph-based provider |
| Monitoring | CloudWatch | Azure Monitor | Maps loosely | Different structure for metrics, logs, alerts |
| Event notification | EventBridge rule → SNS topic → email | Activity Log alert + Action Group (or Event Grid) | Maps loosely | Used on Days 1-3 for instance state alerts |
| Cost safety net | Budgets with email alerts | Cost Management budgets | Maps directly | Set before any lab, on both clouds |
| Serverless | Lambda | Azure Functions | Maps directly | **Placeholder** for the bonus labs |
| Managed database | RDS / Aurora | Azure SQL Database (and related services) | Maps loosely | **Placeholder** for the bonus labs |
| Device management | none | Intune | **Azure/Microsoft-only** | Cannot be prepared in AWS |
| Directory and identity for devices | none (IAM Identity Center is loosely related) | Entra ID | **Azure/Microsoft-only** | Core of the recruiter's ask |

A lesson that transfers directly: on AWS, `plan` passed but `apply` failed because the instance type wasn't allowed on the Free Tier account. Azure has the same class of problem (VM size availability, quotas, trial limits), so expect `plan` to pass and `apply` to fail there too.

---

## 2. Backup, snapshot and restore (focus area)

### 2.1 Concept mapping

| Concept | AWS (done in lab) | Azure (planned) | Mapping |
|---|---|---|---|
| Disk snapshot | EBS snapshot: point-in-time, incremental, regional, exists independently of the volume | Managed disk snapshot: exists independently of the source disk and can create new disks when a VM is rebuilt | Maps directly |
| Restore a disk from a snapshot | New volume from `snapshot_id`, attached to an instance | New managed disk from a snapshot, attached to a VM | Maps directly |
| Whole-machine template | AMI (points at snapshots plus launch settings) | Managed image or Compute Gallery image | Maps loosely |
| Managed backup service | AWS Backup | Azure Backup | Maps loosely |
| Where recovery points live | Backup vault | Recovery Services vault (a newer Backup vault type exists for some workloads) | Maps loosely |
| Schedule and retention | Backup plan rule | Backup policy | Maps loosely |
| What gets backed up | Tag-based selection (`backup = daily`) | VMs assigned to a policy, one by one, or enrolled through Azure Policy, *verify* | Maps loosely |
| Application-consistent backup | VSS-based tooling for Windows (via AWS Backup / Systems Manager), *verify* | Azure Backup uses VSS on Windows VMs and user-defined scripts on Linux VMs | Maps directly in concept |
| Protection against deletion | Vault lock, copies to another region or account | Soft delete (enabled by default, keeps deleted backup data an extra 14 days), plus options such as immutable vaults and Multi-User Authorization, *verify* | Maps loosely |
| Disaster recovery | Cross-region copies (and dedicated DR services) | Azure Site Recovery: orchestrates failover and failback across VMs | Maps loosely |
| Check for leftovers | `aws ec2 describe-snapshots --owner-ids self` | `az snapshot list` | Maps directly |

### 2.2 Restore options

| Goal | AWS | Azure |
|---|---|---|
| Get a **disk** back | Volume from snapshot, attach to an instance | Restore disks, then attach to a VM |
| Get a **whole machine** back | Snapshot → AMI → launch, or swap the root volume of a stopped instance | Azure Backup "Create new VM" from a restore point |
| Roll back an **existing** machine | Replace root volume (check the docs) | Azure Backup "Replace existing", which takes a snapshot of the existing VM first. Has limitations (for example unencrypted managed VMs), *verify* |
| Recover **individual files** | Mount a restored volume and copy files | File recovery from a restore point |

### 2.3 Scenario mapping: lab exercises

| # | Scenario | AWS lab (done, Day 4) | Azure lab (planned) |
|---|---|---|---|
| 1 | Snapshot before a risky change, by hand | `aws ec2 create-snapshot` | `az snapshot create` |
| 2 | Restore a data volume into a new instance | Volume with `snapshot_id`, attached, mounted without `mkfs` | Managed disk created from a snapshot, attached, mounted without formatting |
| 3 | Snapshot managed by Terraform, and what `destroy` does to it | `aws_ebs_snapshot` | `azurerm_snapshot`, same lifecycle lesson |
| 4 | Simulated disaster: destroy and rebuild | `terraform destroy`, rebuild with one added line | Same exercise |
| 5 | Whole-machine template | AMI, deregister then delete its snapshot | Image from a VM, clean up the image and its source |
| 6 | **Production-style managed backup** | **Not practiced yet.** Candidate lab: AWS Backup vault, plan, tag-based selection | Recovery Services vault, backup policy, protected VM, restore to a new VM. **Planned** |
| 7 | Orphan check after teardown | Four-point CLI verification | Equivalent `az` checks |

Scenario 6 is the one that matches how production works, and it has not been practiced on either cloud yet. It is the priority backup lab for the Azure phase.

### 2.4 Production design: policy vs. data

The lesson from Day 4: **a backup must not share a lifecycle with what it protects.**

- **Policy** (schedule, retention, scope) is Terraform code, in its own project and state, owned by the platform/infra team.
- **Data** (recovery points) lives in a vault, outside the workload's lifecycle, ideally locked and copied to another region or account.
- **Workloads** only opt in, for example with a tag on AWS, or a policy assignment on Azure.
- **Restores are tested** on a schedule, and the measured time is compared with the RTO.
- **Alerts** fire on backup job failures, not only on instance state.

### 2.5 Terraform resources

| Purpose | AWS | Azure (*verify* arguments in provider docs) |
|---|---|---|
| Disk | `aws_ebs_volume` | `azurerm_managed_disk` |
| Attach disk | `aws_volume_attachment` | `azurerm_virtual_machine_data_disk_attachment` |
| Snapshot | `aws_ebs_snapshot` | `azurerm_snapshot` |
| Restore from snapshot | `snapshot_id` on the volume | `create_option = "Copy"` with `source_resource_id` on the disk |
| Backup vault | `aws_backup_vault` | `azurerm_recovery_services_vault` |
| Backup schedule and retention | `aws_backup_plan` | `azurerm_backup_policy_vm` |
| What is backed up | `aws_backup_selection` | `azurerm_backup_protected_vm` |

**Teardown warning for the Azure backup lab:** a vault that contains protected items or soft-deleted backup data may not simply be removed by `terraform destroy`. Plan the cleanup order and check the docs before running the lab, so no vault or backup data is left behind.

---

## 3. Terraform state and automation

| Area | AWS (done in lab) | Azure (planned) |
|---|---|---|
| Remote state backend | S3 bucket with versioning and `use_lockfile = true` | `azurerm` backend on Blob Storage: locking through a blob lease, versioning on the storage account, *verify* |
| Bootstrap problem | Bucket created once with the AWS CLI | Storage account and container created once with `az` |
| Handoff to Ansible | `local_file` writes `inventory.ini` from the instance IP | Same pattern with the VM's IP |
| Pipeline credentials | Not yet wired | Workload identity federation or a service principal |

---

## 4. Things that do not map

- **Intune** has no AWS counterpart. It must be learned directly in a Microsoft 365 / Azure tenant, using a trial, with a time-limited clock.
- **Entra ID vs. IAM:** similar goals, different models. Entra ID is the identity source for users, devices and apps. AWS IAM is mainly permissions for AWS resources.
- **CloudWatch vs. Azure Monitor** and **EventBridge vs. Event Grid / Action Groups:** treat as "inspired by", not as the same exercise.
- **Windows password retrieval** (RSA key decryption) exists only on AWS.

---

## 5. Lab vs. production summary (whole week)

| Topic | What I did in the lab | How production usually does it |
|---|---|---|
| Terraform state | Local file first, then S3 | Remote state with locking and strict access control |
| Identity | One IAM admin user with broad permissions | Least privilege, roles, SSO or federation, MFA |
| Credentials | Long-lived access keys on my laptop | No long-lived keys: short-lived credentials, pipelines use workload identity |
| Network | Default VPC, SSH and RDP from my own IP | Dedicated networks, no direct public SSH or RDP: bastion, VPN or managed session access |
| Making changes | One person applies from a laptop | Pull request, reviewed `plan`, pipeline, approval gate |
| Environments | One, torn down after each session | Separate dev, test and prod, with separate states, often separate accounts |
| Configuration | By hand over SSH, plus a small Ansible playbook | Ansible, user data or pre-built images, all repeatable |
| Backups | A snapshot by CLI and by Terraform, in the same project | Scheduled backup service, separate lifecycle, locked vault, cross-region or cross-account copies |
| Restore testing | Once, by hand | Scheduled, measured against the RTO |
| Monitoring | Raw SNS emails on instance state | Dashboards, structured alerts, backup failure alerts, on-call |
| Secrets | None used | Secrets manager or Key Vault, never in code |
| Cost control | Manual teardown and budget alerts | Tagging, budgets, scheduled stop, cleanup policies |

---

## 6. Planned Azure labs (mirror of the AWS week)

1. **Linux VM and NSG** with `azurerm`, authentication through `az login`
2. **Terraform with Ansible** against the Azure VM, same inventory handoff
3. **Windows VM with remote state** in Blob Storage, RDP, admin password set at creation
4. **Snapshots, backup and restore:** scenarios 1-5 from section 2.3, then **scenario 6** (vault, policy, protected VM, restore to a new VM), then a verified clean teardown
5. **Entra ID** with the `azuread` provider
6. **Intune** in a dedicated test tenant, starting the trial only when the earlier labs are proven, because of its time limit

Before activating the Azure trial: finish a written checklist for each lab above, so the trial days are spent executing a plan instead of improvising.

---

## 7. Open items to verify when practicing

- Azure dynamic vs. static public IP behavior on stop and start
- Azure stopped vs. stopped (deallocated) billing behavior
- Exact `azurerm` arguments for snapshots, disks, and backup resources
- Azure Policy options to enroll VMs in backup automatically
- "Replace existing" restore limitations and soft-delete behavior when tearing down a vault
- Current AWS VSS tooling for application-consistent Windows backups
- Backend locking and versioning details for the `azurerm` backend

Reference used for the Azure backup and restore options: Microsoft Learn, "Backup and restore options for virtual machines in Azure" (https://learn.microsoft.com/azure/virtual-machines/backup-recovery) and "How to restore Azure VM data in Azure portal".
