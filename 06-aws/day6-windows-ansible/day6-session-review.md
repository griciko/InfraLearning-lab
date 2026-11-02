# Day 6 — Session Review (step by step)

A chronological review of the whole Day 6 session. Command-level detail is in `steps-summary.md`, and the question-by-question notes are in `review-qa.md`.

**Status reminder:** everything here is lab work in a personal AWS account, not production experience.

---

## 1. Preparation

1. Checked the repo, the AWS identity, and the leftovers script (CLEAN).
2. Checked Ansible in WSL: the collections `ansible.windows` and `community.windows`, and the `pywinrm` library.
3. Prepared the Windows RSA key, its key pair name, and the instance type that worked on Day 3.
4. Learned the differences from Linux: WinRM instead of SSH, PowerShell modules instead of Python, two collections, ports 5985 and 5986, and the transports.

---

## 2. The lab

| # | Step | Key result |
|---|---|---|
| 1 | Terraform: Windows Server with a user-data script that enables WinRM over HTTPS, security group, data volume, generated inventory, `group_vars` | 5 resources |
| 2 | First `apply` failed: key pair name included `.pem` | Fixed with `describe-key-pairs`, optional data source and validation |
| 3 | Connected: port test, password decrypted in the console, silent prompt, `win_ping` | `True` and `pong` |
| 4 | First look: disk list | Disk 0 system (MBR), disk 1 RAW 2 GB |
| 5 | IIS playbook | First run changed, second run `ok` |
| 6 | Data disk playbook: select by state, assert, initialize, partition, format, test file | First run changed, second run `ok` with initialize skipped |
| 7 | Drift: hand edit, `--check --diff`, repair | Only the page task showed `changed` |
| 8 | Optional baseline playbook (registry, environment variable, Windows Server Backup feature, service query) | Install something, change something |
| 9 | Teardown with the leftovers script before and after | Expected: CLEAN, exit code 0 |

---

## 3. Review and corrections

- **Password:** correct. Added the "why": files can leak, the prompt keeps it out of the history, and the password is random per instance.
- **HTTPS with NTLM:** the first answer described the lab instead of answering. The point: 5986 is WinRM over HTTPS, NTLM fits a local account, and the lab-only parts were the self-signed certificate with validation off and WinRM reachable from the internet.
- **Disk selection:** the idea (select by state) was right. Missing: the `assert` that refuses to guess, the RAW guard, `win_format` without `force`, and `force: false` on the file, which together make the second run safe.
- **`ok`, `changed`, `skipped`:** correct. `skipped` means the task didn't run at all.
- **Check mode on the disk playbook:** the concern about erasing data was wrong. Check mode doesn't execute changes, and the format task has no `force`. The real problem is a **misleading preview**, because on a RAW disk the earlier steps are only simulated.
- **Two corrections from my side:** I had assumed the firewall module is in `ansible.windows`, but it is in `community.windows` (check with `ansible-doc`). And the teardown result wasn't reported, so the documents state the expected result.

---

## 4. Documents produced

| File | Where to put it | Purpose |
|---|---|---|
| `day6-steps.md` | `06-aws/day6-windows-ansible/steps-summary.md` | Command-level steps |
| `day6-review-qa.md` | `06-aws/day6-windows-ansible/review-qa.md` | Review answers with corrections, plus lab-vs-production and interview framing |
| `day6-session-review.md` | `06-aws/day6-windows-ansible/session-review.md` | This chronological review |
| `aws-azure-mapping.md` (updated) | `docs/aws-azure-mapping.md` | New section on Windows servers with Ansible over WinRM |

The playbooks, `winrm-setup.ps1`, and `group_vars/win.yml` stay in the project folder.

---

## 5. Key lessons

- Ansible on Windows is the same pattern with a different transport (WinRM) and PowerShell modules
- The password never goes into a file: a silent prompt and an environment variable
- A key pair name is not the `.pem` file name, and `plan` can't verify what lives outside the code
- Check which collection a module is in with `ansible-doc`, don't assume
- Select a disk by state or ID, never by a hardcoded number, and refuse to guess with an `assert`
- Guard destructive steps: initialize only when RAW, format without `force`, files with `force: false`
- `ok` means checked and matching, `changed` means modified, `skipped` means not run
- Check mode previews without changing anything, but dependent steps can make the preview misleading
- Hand edits to a managed server get overwritten: change the playbook
- User data runs only at first boot, so a changed script means a new instance

---

## 6. Open items

- Azure phase: repeat this on an Azure Windows VM with the same playbooks. How WinRM gets enabled there, and how the admin password is handled, still need to be checked
- Production topics not practiced: Kerberos with a domain, a trusted certificate, secrets in a vault, patching with `win_updates`, roles and pipeline runs
- Housekeeping: update the root `README.md` (Ansible on Windows as Done) and `docs/notes-and-lessons.md`, check `git status` for `terraform.tfvars` and `ansible/inventory.ini`, then commit
