# AWS — Day 2: Review Q&A

Notes from the review session after connecting Terraform and Ansible against a real EC2 instance: automatic inventory generation, a WSL/Windows filesystem permissions issue, a missing security group rule, live idempotency, the Day 1 notification chain fully verified, and a newly discovered EC2 networking behavior.

---

### 1. How did Terraform's `local_file` resource connect to Ansible — what exactly got passed from one tool to the other?

Terraform and Ansible are completely separate tools — neither is aware the other exists, and there's no API or plugin connecting them directly. The "integration" is simply: **one tool's output becomes the other tool's input, through a shared file.** Terraform knew the EC2 instance's public IP (`aws_instance.lab_vm.public_ip`) from its own state, and the `local_file` resource wrote that value into a plain text file (`inventory.ini`), formatted the way Ansible expects an inventory file to look. Ansible then read that file as input, with no awareness of how it was generated — the same as if the IP had been typed in by hand. The only thing passed between the two tools was a public IP address, inside a text file they both happened to agree on the format of. This is a common DevOps pattern more broadly: tool A's output file becomes tool B's input file, with nothing fancier connecting them.

---

### 2. Why did the first `curl`/browser test fail before the security group fix, and what did that reveal?

The curl/browser check failed because of the security group restriction — from the initial setup, only port 22 (SSH) was allowed inbound. Port 80 (HTTP) had no rule at all, so the request couldn't reach the instance. Adding a second `ingress` block for port 80, scoped to the same IP, fixed it and the test passed. This revealed a real gap in the original Day 2 setup: the security group was copied from Day 1 (an SSH-only lab) without considering that this lab's actual goal — testing a web server — needed HTTP access too.

---

### 3. Why couldn't `chmod` fix the `.pem` file permissions when accessed via `/mnt/d/`, and what was the actual fix?

`chmod` couldn't change anything on a file accessed through `/mnt/d/`, even as root. The reason isn't a permissions mistake — it's a filesystem limitation: Windows drives mounted into WSL (`/mnt/c/`, `/mnt/d/`, etc.) use a bridge filesystem (`drvfs`) that has **no support for Linux permission bits at all**, so there's nothing for `chmod` to actually modify there. The fix was to copy the `.pem` key into WSL's own native filesystem (`~/.ssh/`), where Linux permissions work normally, and `chmod 400` could be applied successfully.

---

### 4. If `index.html` were hand-edited directly on the instance instead of through the playbook, what would happen on the next playbook run?

Any manual change made directly on the instance would be silently overwritten the next time the playbook ran, since Ansible's `copy` task declares the file's content as a fixed desired state and reapplies it regardless of what's currently there. The correct approach is to make the change in the playbook itself (`playbook.yml`) and re-run it — that way the change is reproducible, tracked in code, and survives if the instance is ever rebuilt. This was proven live: editing the content in the playbook and re-running it showed `changed`, and the live page reflected the new text.

---

### 5. Why did the public IP change after stop/start, and what are the two ways to handle that?

This is standard AWS behavior, not a misconfiguration: EC2 instances get a dynamic public IP by default, which is only guaranteed to stay the same while the instance runs continuously. Stopping an instance releases that public IP back into AWS's pool; starting it again assigns a new one. (The private IP, by contrast, typically persists across stop/start.)

Two ways to handle it:
- **Re-run `terraform apply` after any stop/start** — since the inventory file is Terraform-managed, re-applying refreshes it with the current public IP automatically. This fits a workflow of short sessions ending in full termination, rather than long-lived stop/start cycles.
- **Attach an Elastic IP** (`aws_eip`) to the instance — a static public IP that stays attached across stop/start cycles. Better suited to an instance that's repeatedly stopped and restarted over a longer period while needing to stay reachable at the same address. Costs nothing while attached to a running instance, but incurs a small hourly charge if left allocated without being attached to a running instance.

---

*Lab covered: Terraform → Ansible handoff via a generated inventory file, `dnf`-based playbook for Amazon Linux 2023, WSL/Windows filesystem permission boundaries, a missing security group rule caught through real testing, idempotency and "code as source of truth" proven on a live server, full verification of the SNS/EventBridge notification chain with real triggered events, and EC2's dynamic public IP behavior on stop/start.*
