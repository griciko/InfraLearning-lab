# AWS — Day 1: First EC2 Instance with Terraform

Step-by-step summary of what was built, in order. Region used: `eu-north-1`.

---

## Part A — AWS account access setup

1. **Secured the root account** — enabled MFA on the root user, no access key created for root (root is never used for CLI/Terraform work).
2. **Created an IAM user** (`terraform-admin`) in IAM → Users, with the `AdministratorAccess` policy attached directly (broad on purpose for learning; least-privilege to be applied later once familiar with the exact permissions Terraform needs).
3. **Generated an access key** for that IAM user (Security credentials tab → Create access key → CLI use case), saved the Access Key ID and Secret Access Key securely (shown only once).
4. **Installed and configured the AWS CLI** locally:
   ```powershell
   aws configure
   ```
   Entered Access Key ID, Secret Access Key, default region (`eu-north-1`), output format (`json`).
5. **Verified authentication:**
   ```powershell
   aws sts get-caller-identity
   ```
   Confirmed UserId, Account, and Arn returned — authenticated as the IAM user, not root.
6. **Set a billing budget alert** (Billing and Cost Management → Budgets) at $20 and $50 thresholds with email notification, as a safety net before any EC2 work.

---

## Part B — Terraform project: EC2 instance + security group

7. **Created the project folder:**
   ```powershell
   cd ~/infra-learning-lab
   mkdir -p 06-aws/day1-first-ec2
   cd 06-aws/day1-first-ec2
   ```

8. **Wrote the AWS provider block** in `main.tf`, targeting `eu-north-1`.

9. **Added an `aws_ami` data source** to look up the latest Amazon Linux 2023 AMI dynamically, instead of hardcoding a region-specific AMI ID.
   ```powershell
   terraform init
   ```

10. **Retrieved local public IP** (for locking down SSH access):
    ```powershell
    (Invoke-WebRequest -Uri "https://checkip.amazonaws.com").Content.Trim()
    ```

11. **Created an EC2 key pair** in AWS Console (EC2 → Key Pairs), type ED25519, `.pem` format, downloaded to `D:\GITlabs\AWS\key.pem`.

12. **Added to `main.tf`:**
    - `aws_security_group` — allowing inbound SSH (port 22) only from the local IP (`/32`), open egress
    - `aws_instance` — `t3.micro`, using the looked-up AMI, referencing the security group and key pair
    - `output "instance_public_ip"` — to retrieve the IP after apply

13. **Added notification infrastructure** (suggested by AmazonQ, completed with a missing piece):
    - `aws_sns_topic` — SNS topic for alerts
    - `aws_sns_topic_subscription` — email subscription (requires manual confirmation via the email AWS sends after apply)
    - `aws_sns_topic_policy` — **added manually**, since EventBridge cannot publish to an SNS topic without an explicit resource policy granting it permission (missing from the original suggestion)
    - `aws_cloudwatch_event_rule` — matches EC2 state-change events (running, stopped, terminated)
    - `aws_cloudwatch_event_target` — connects the EventBridge rule to the SNS topic

14. **Ran the standard workflow:**
    ```powershell
    terraform fmt
    terraform validate
    terraform plan
    terraform apply
    ```
    Reviewed the plan, confirmed the dependency order (security group created before the instance, since the instance references the security group's ID).

15. **Confirmed the SNS email subscription** by clicking the confirmation link in the inbox after apply.

---

## Part C — Connecting to the instance

16. **Retrieved the public IP:**
    ```powershell
    terraform output
    ```

17. **First SSH attempt failed** with:
    ```
    Permissions for '*.pem' are too open.
    ```

18. **Diagnosed and fixed Windows file permissions on the `.pem` key**, using `icacls`:
    - Initial partial fix (`/inheritance:r` + `/grant:r`) left two broad-access entries still present: `NT AUTHORITY\Authenticated Users` and `BUILTIN\Users`
    - Checked current permissions:
      ```powershell
      icacls "D:\GITlabs\AWS\key.pem"
      ```
    - Removed the remaining broad entries explicitly:
      ```powershell
      icacls "D:\GITlabs\AWS\key.pem" /remove:g "NT AUTHORITY\Authenticated Users"
      icacls "D:\GITlabs\AWS\key.pem" /remove:g "BUILTIN\Users"
      ```
    - Verified only three entries remained: the local user (R), `BUILTIN\Administrators` (F), `NT AUTHORITY\SYSTEM` (F) — all acceptable to SSH.

19. **Connected successfully:**
    ```powershell
    ssh -i "D:\GITlabs\AWS\key.pem" ec2-user@<public-ip>
    ```
    Ran sanity commands (`whoami`, `uname -a`), confirmed access to the real, Terraform-provisioned instance, and took a screenshot.

---

## Part D — Teardown and verification

20. **Reviewed and ran destroy:**
    ```powershell
    terraform plan -destroy
    terraform destroy
    ```

21. **Confirmed cleanup in AWS Console:**
    - EC2 instance showed as "Terminated" (remains visible in the console for about an hour post-termination before disappearing — not an active/billed resource)
    - Security group (`terraform-lab-sg`) removed
    - No orphaned EBS volumes left behind (root volume deleted automatically on termination, per default "Delete on Termination" setting)

22. **Verified no leftover storage via CLI:**
    ```powershell
    aws ec2 describe-volumes --filters "Name=status,Values=available"
    ```
    Returned empty — confirming no unattached volumes accruing cost.

---

*Result: a full, working Terraform-provisioned AWS EC2 lab — IAM access setup, dynamic AMI lookup, locked-down security group, SNS/EventBridge notifications, SSH access with a real Windows permissions fix, and clean teardown with verification.*
