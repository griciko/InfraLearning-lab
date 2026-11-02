# AWS — Day 1: Review Q&A

Notes from the review session after the first EC2 lab: IAM setup, Terraform-provisioned EC2 instance with a locked-down security group, SNS/EventBridge notifications, SSH access with a Windows permissions fix, and clean teardown.

---

### 1. Why did the security group need to reference your specific IP instead of `0.0.0.0/0`?

To restrict inbound access so that only traffic from a known source (the local IP, `/32`) using a specific protocol and port (SSH, port 22) could reach the instance. `0.0.0.0/0` would allow SSH attempts from anywhere on the internet — the security group is the equivalent of a firewall rule, and narrowing both the source and the port is standard practice for any internet-facing resource, even a lab one.

---

### 2. What was the dependency chain Terraform resolved automatically today?

The EC2 instance's configuration referenced the security group by its Terraform ID (`vpc_security_group_ids = [aws_security_group.lab_sg.id]`). Terraform read that reference and determined the security group had to exist before the instance could be created — without anything explicitly stating "create this first." The same pattern applied to the notification chain: the EventBridge target referenced the SNS topic's ARN, so the topic was created before the target that connects to it. This is Terraform building the correct creation order automatically from resource references in the code, rather than the order resources happen to be written in the file.

---

### 3. Why did SSH reject the `.pem` file initially, and what did `icacls` actually fix?

SSH refuses to use a private key file that's accessible by more than just the owning user — on Windows, a freshly downloaded `.pem` file by default includes broader access entries (e.g. `BUILTIN\Users`, `NT AUTHORITY\Authenticated Users`) inherited from the folder. `icacls` was used to strip those broader entries and leave only the specific user (read-only) plus `SYSTEM`/`Administrators` (which SSH accepts, since they represent the OS and local elevated admin rather than arbitrary accounts) — matching the restricted-access requirement SSH enforces for private keys.

---

### 4. Why does the EventBridge → SNS notification chain need a separate SNS topic policy?

By default, EventBridge has no permission to publish to an SNS topic — the topic needs an explicit resource policy granting `SNS:Publish` to the EventBridge service principal. Without it, the rule and target create successfully but notifications never actually arrive, since the final publish step is silently denied. Separately: when checking after the lab, no SNS topic or subscription were found — this was expected, since `terraform destroy` removed the entire notification chain along with the EC2 instance, not evidence of a separate issue. Whether a notification actually fired during the window the resources existed is still open to verify (check the inbox, including spam, on the next run) — parked for a future session rather than fixed immediately.

---

### 5. What's the practical difference between "terminated" and "stopped" in terms of what you're actually paying for?

**Terminated** is irreversible — the instance is permanently deleted and cannot be restored or restarted; the attached root EBS volume is also deleted by default. No compute or storage charges continue once terminated. (Separately, **Reserved Instances** are a different, unrelated pricing model — committing upfront to 1 or 3 years of usage for a discount versus on-demand. That's a capacity-planning/cost decision made by whoever owns infrastructure budget or architecture, based on a known long-term workload — not a routine day-to-day admin decision, though an admin might be the one to notice a workload has become stable enough to flag it as a reservation candidate.)

**Stopped** is reversible — the instance is shut down but can be started again anytime, useful for maintenance or when installing something without needing to keep it running continuously. A stopped instance is **not billed for compute or data transfer**, but the attached EBS storage volume still exists and continues to incur its (small) per-GB/month storage charge while stopped. Also worth noting operationally: after a stop/start cycle, the instance's "launch time" doesn't reflect actual historical uptime — worth being aware of when reviewing an instance's history.

---

*Lab covered: IAM user setup (vs. root), AWS CLI authentication, dynamic AMI lookup via data source, security group with IP/port restriction, EC2 instance provisioning, SNS/EventBridge notification chain (including the missing topic policy), SSH key permission troubleshooting on Windows via `icacls`, and verified teardown with no orphaned resources.*
