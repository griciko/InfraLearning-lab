# AWS — Day 3: Windows EC2 + Remote State (S3)

Step-by-step summary of what was built, in order. Region: `eu-north-1`. Builds on Days 1-2, now with a Windows Server instance reached over RDP and Terraform state moved from the laptop into an S3 bucket.

---

## Part A — Pre-checks

1. **Checked the Terraform version:**
   ```powershell
   terraform -version
   ```
   Result: 1.16.4. Native S3 state locking (`use_lockfile`) needs 1.10 or newer, so no upgrade was needed.

2. **Created a new RSA key pair** (EC2 → Key Pairs, type RSA, `.pem` format), saved as `D:\GITlabs\AWS\key.pem`. This corrected the Day 1 setup: the ED25519 key works for Linux SSH, but AWS can only decrypt a Windows Administrator password with an RSA key. No `icacls` fix was needed, since this key is used in the Console to decrypt the password, not with SSH.

---

## Part B — S3 bucket for remote state (bootstrap, via CLI)

Terraform can't create the bucket that stores its own state (the state needs the bucket to exist first), so the bucket is created once, outside the project.

3. **Built a globally unique bucket name from the account ID:**
   ```powershell
   $accountId = aws sts get-caller-identity --query Account --output text
   $bucket = "ts-$accountId-eu-north-1"
   ```

4. **Created the bucket** (`eu-north-1` requires an explicit `LocationConstraint`):
   ```powershell
   aws s3api create-bucket --bucket $bucket --region eu-north-1 --create-bucket-configuration LocationConstraint=eu-north-1
   ```

5. **Enabled versioning**, so every previous state file is kept:
   ```powershell
   aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled
   ```

6. **Blocked all public access:**
   ```powershell
   aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
   ```
   New buckets are already encrypted at rest by default (SSE-S3), so no separate encryption step was needed. Verified with `aws s3 ls`.

---

## Part C — Terraform project: Windows instance

7. **Created the project folder, one step at a time:**
   ```powershell
   cd ~/infra-learning-lab
   cd 06-aws
   mkdir day3-windows-remote-state
   cd day3-windows-remote-state
   ```

8. **Retrieved the current public IP** for the security group rule.

9. **Wrote `main.tf`** (commented, block by block) with:
   - AWS provider for `eu-north-1`
   - `aws_ami` data source for the latest Amazon-provided Windows Server 2022 image
   - Security group allowing RDP (port 3389) only from my IP
   - EC2 instance with an explicit 30 GB gp3 root disk and `delete_on_termination = true`
   - Outputs for the public IP and instance ID

10. **Ran the workflow with local state first:**
    ```powershell
    terraform init
    terraform fmt
    terraform validate
    terraform plan
    terraform apply
    ```

---

## Part D — Troubleshooting: instance type rejected

11. **`apply` failed** because `t3.medium` is not available on the Free Tier account, even though `plan` passed. `plan` only checks the code and provider rules and can't know the account's restrictions, so only the real API call revealed it.

    **Was anything created?** Yes. Terraform doesn't roll back. It builds in dependency order and keeps what already succeeded: the security group (no dependencies) was created, the instance (rejected) was not. Anything independent of the instance, such as the SNS resources, was created as well. `terraform state list` shows what is currently tracked.

    **Fix:** switched to `c7i-flex.large` (similar CPU and RAM, allowed on the account), edited `main.tf`, and ran `apply` again. Terraform compared code against state, saw only the instance missing, and created just that.

---

## Part E — Migrating state to S3

12. **Added a `backend "s3"` block** inside the existing `terraform { }` block, after `required_providers`:
    ```hcl
    # Store state in S3 instead of on this laptop
    backend "s3" {
      bucket       = "<bucket-name>"
      key          = "day3-windows/terraform.tfstate"
      region       = "eu-north-1"
      encrypt      = true
      use_lockfile = true
    }
    ```
    Backend blocks can't use variables, so the bucket name is written literally.

13. **Migrated the state:**
    ```powershell
    terraform init -migrate-state
    ```
    Answered `yes` to copy the existing state to the new backend.

14. **Verified:** the state file appeared under `day3-windows/` in the bucket (`aws s3 ls`), and `terraform plan` reported no changes, confirming the migrated state matches reality.

---

## Part F — Accessing the Windows instance

15. **Retrieved the Administrator password:** Console → EC2 → Connect → RDP client → Get password, decrypted with the RSA `.pem`. (On first boot Windows generates the password, AWS encrypts it with the key pair's public half, and the private `.pem` decrypts it. Windows needs 4-10 minutes after launch before it's available.)

16. **Connected over RDP** (`mstsc /v:<public-ip>` and the RDP file from AWS both worked), logged in as `Administrator`.

---

## Part G — Extras

17. **Stop/start test:** stopped and started the instance, confirmed the public IP changed, re-ran `terraform apply` to refresh the output, and connected over RDP again. Same dynamic-IP behavior as Day 2.

18. **Reused the SNS/EventBridge notification block** from Day 2 in this project's `main.tf`. Worked without issues.

19. **Inspected state versions in S3:**
    ```powershell
    aws s3api list-object-versions --bucket $bucket --prefix day3-windows/
    ```
    Several versions were visible after only a few applies. A new version is written whenever the state is written: the migration, the failed apply, the corrected apply, the stop/start re-apply, the SNS apply, and the destroy. With `use_lockfile = true`, small `.tflock` lock objects also appear in the list, so entries ending in `.tflock` are locks and the rest are real state history.

---

## Part H — Teardown

20. **Reviewed and destroyed:**
    ```powershell
    terraform plan -destroy
    terraform destroy
    ```

21. **Verified cleanup:**
    ```powershell
    aws ec2 describe-volumes --filters "Name=status,Values=available"
    ```
    Empty result, so no orphaned volumes. Instance terminated, security group removed.

22. **Looked at the state file after destroy:** 181 bytes, containing only the format version, Terraform version, `serial`, and `lineage`. That is correct, since Terraform manages nothing at that point. `serial` increases on every state write, and `lineage` is a unique ID that stops two unrelated state files from being mixed up. The S3 bucket stays in place for future days.

---

*Result: a Terraform-built Windows Server 2022 instance reached over RDP, a versioned and locked S3 backend with a live state migration, a real partial-failure scenario understood (no rollback, only the failed resource missing), and the first look at state version history.*
