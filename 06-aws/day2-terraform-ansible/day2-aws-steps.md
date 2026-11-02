# AWS — Day 2: Terraform + Ansible Together

Step-by-step summary of what was built, in order. Region: `eu-north-1`. Builds directly on Day 1's EC2 + security group pattern, now connected to Ansible for real configuration management.

---

## Part A — Terraform: EC2 instance + security group (rebuilt from Day 1)

1. **Created the project folder, one step at a time:**
   ```powershell
   cd ~/infra-learning-lab
   mkdir 06-aws
   cd 06-aws
   mkdir day2-terraform-ansible
   cd day2-terraform-ansible
   ```

2. **Retrieved current public IP** (noted it can differ from Day 1's, since ISPs reassign dynamic IPs):
   ```powershell
   (Invoke-WebRequest -Uri "https://checkip.amazonaws.com").Content.Trim()
   ```

3. **Wrote `main.tf`** with the AWS provider, an `aws_ami` data source (latest Amazon Linux 2023), a security group, and an EC2 instance — same pattern as Day 1, now with comments on every block.

4. **Initial security group only allowed port 22 (SSH)** — matching Day 1 exactly.

5. Ran the standard workflow:
   ```powershell
   terraform init
   terraform fmt
   terraform validate
   terraform plan
   terraform apply
   ```

---

## Part B — Connecting Terraform's output to Ansible

6. **Added a `local_file` resource** to `main.tf`, writing the instance's public IP directly into an `inventory.ini` file in the correct Ansible format — removing the need to manually copy-paste the IP. This is the entire "integration" between the two tools: Terraform writes a plain text file, Ansible reads it as input. Neither tool is aware the other exists.

   ```hcl
   resource "local_file" "ansible_inventory" {
     filename = "${path.module}/inventory.ini"
     content  = <<-EOT
       [lab]
       ${aws_instance.lab_vm.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
     EOT
   }
   ```

7. **Re-initialized** (new `local` provider) and applied:
   ```powershell
   terraform init
   terraform apply
   ```

8. **Verified the inventory file was generated correctly** with a real IP, no manual editing:
   ```powershell
   Get-Content inventory.ini
   ```

9. **Confirmed SSH reachability manually once**, same as Day 1, before handing off to Ansible.

---

## Part C — Ansible playbook against the real EC2 instance

10. **Created the Ansible project in WSL:**
    ```bash
    cd ~
    mkdir infra-learning-lab-ansible-aws
    cd infra-learning-lab-ansible-aws
    ```

11. **Wrote `playbook.yml`** — installs nginx (using `dnf`, since Amazon Linux 2023 is RPM-based, not Debian-based like the earlier local Ansible labs), starts and enables the service, and deploys a custom `index.html`.

---

## Part D — Troubleshooting: crossing from WSL to the Windows filesystem

12. **First playbook run failed** — `UNREACHABLE`, `"no such identity: D:/GITlabs/AWS/key.pem"` — because the inventory file (generated on the Windows side) referenced a **Windows-style path**, which WSL doesn't understand. Needed `/mnt/d/...` instead.

13. **Attempted `chmod 400` on the `.pem` file via `/mnt/d/...`** — failed with `Permission denied`, even with `sudo`. Root cause: Windows drives mounted into WSL (`/mnt/c/`, `/mnt/d/`) use a filesystem bridge (`drvfs`) with **no support for Linux permission bits at all** — not a permissions mistake, a filesystem limitation. `chmod` has nothing to actually change there.

14. **Fix:** copied the `.pem` key into WSL's own native filesystem, where Linux permissions work normally:
    ```bash
    mkdir -p ~/.ssh
    cp /mnt/d/GITlabs/AWS/key.pem ~/.ssh/key.pem
    chmod 400 ~/.ssh/key.pem
    ```

15. **Updated `main.tf`'s `local_file` content** to reference `~/.ssh/key.pem` (the WSL-native path) instead of the Windows path, then re-applied:
    ```powershell
    terraform apply
    ```

16. **Ran the playbook successfully:**
    ```bash
    ansible-playbook -i /mnt/d/GITlabs/infra-learning-lab/06-aws/day2-terraform-ansible/inventory.ini playbook.yml
    ```

---

## Part E — Testing, and a second security group fix

17. **Attempted to test the nginx page over HTTP** (`curl`/browser on port 80) — failed, because the security group only allowed port 22. **Added a second `ingress` block** to `aws_security_group` for port 80, scoped to the same IP:
    ```powershell
    terraform plan
    terraform apply
    ```

18. **Verified successfully** — nginx page reachable, showing the custom HTML deployed by the playbook.

19. **Tested idempotency and "code as source of truth" live:** edited the `index.html` content in `playbook.yml`, re-ran the playbook — task reported `changed`. Confirmed the updated text appeared on the live page. Discussed why a manual edit directly on the instance would be silently overwritten on the next playbook run, and why the playbook (not the live server) is the correct place to make changes.

---

## Part F — Revisiting Day 1's parked notification chain

20. **Added the SNS/EventBridge notification block** (topic, email subscription, topic policy, EventBridge rule, event target) to today's `main.tf` — the same pattern from Day 1, now with the topic policy fix already included from the start.
    ```powershell
    terraform init
    terraform apply
    ```

21. **Confirmed the SNS email subscription** via the confirmation link.

22. **Triggered real state-change events to test the chain end to end:**
    ```powershell
    aws ec2 stop-instances --instance-ids <instance-id>
    aws ec2 start-instances --instance-ids <instance-id>
    ```
    Both `stopped` and `running` events arrived by email, correctly containing the instance ID, region, account, and timestamp — confirming the full chain (EventBridge → SNS → email) works. Noted the message format is raw EventBridge JSON, not human-formatted — parked as a future improvement, likely via a Lambda function to transform the message, tying into the AWS bonus credit for Lambda mentioned earlier.

23. **Observed and diagnosed a new issue from the stop/start test:** the instance received a **new public IP** after restarting. Identified the cause — EC2 public IPs are dynamic by default and are released back to AWS's pool on stop, with a new one assigned on start (unlike the private IP, which persists). Discussed two fixes:
    - Re-run `terraform apply` after any stop/start to refresh the IP in `inventory.ini` (fits this project's actual usage pattern — spin up, test, terminate)
    - Attach an **Elastic IP** (`aws_eip`) for a fixed address across stop/start cycles — better suited to a longer-lived instance stopped/started repeatedly over time, not the current short-session pattern

---

## Part G — Teardown

24. **Ran destroy, reviewed first:**
    ```powershell
    terraform plan -destroy
    terraform destroy
    ```

25. **Verified cleanup** in AWS Console — EC2 instance terminated, security group removed, SNS topic and EventBridge rule removed, no orphaned resources.

---

*Result: a full Terraform → Ansible workflow against real AWS infrastructure — automatic inventory generation, a real cross-filesystem (WSL ↔ Windows) troubleshooting detour, a missing security group rule caught by testing, idempotency proven live on a real server, the Day 1 notification chain fully verified with real trigger events, and a newly discovered EC2 networking behavior (dynamic public IP on stop/start) understood and solved two ways.*
