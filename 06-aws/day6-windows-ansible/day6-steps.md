# Day 6 — Steps Summary

Ansible on Windows over WinRM, with Terraform building the server. Region: `eu-north-1`.

**Lab vs. production:** everything here is lab work in a personal AWS account. Each part notes where production differs.

---

## Part A — Preparation

1. Repo up to date, AWS CLI on the admin profile, leftovers script reporting CLEAN.
2. **Ansible in WSL:** the collections `ansible.windows` and `community.windows` present (the disk and firewall modules are in `community.windows`), and `pywinrm` importable by the Python Ansible uses.
3. **Windows key:** the RSA key from Day 3 (used only to decrypt the Windows password), its key pair **name** from the AWS console, and the instance type that worked on Day 3 (`c7i-flex.large`).

---

## Part B — Terraform: Windows server with WinRM enabled

Project folder `06-aws/day6-windows-ansible`, created one step at a time, with an `ansible/` and `ansible/group_vars/` folder.

4. **Files:** `versions.tf` (S3 backend, own state key), `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars` (real values, Git-ignored), `example.tfvars` (placeholders), `winrm-setup.ps1`.
5. **`winrm-setup.ps1`** runs once at first boot through EC2 user data (EC2Launch v2, inside `<powershell>` tags): starts WinRM, creates the base configuration if missing, creates a **self-signed certificate** (30 days), removes the HTTP listener, creates an **HTTPS listener** on 5986, and opens port 5986 in the Windows Firewall. It is written inline in the repo, so nothing is downloaded at boot.
6. **Five resources:** security group (5986, 3389 and 80, all from my IP only), Windows Server 2022 instance (`user_data_replace_on_change = true`, because the script only runs at first boot), a 2 GB data volume, the attachment, and the generated `ansible/inventory.ini` (only the host, in a `[win]` group).
7. **`ansible/group_vars/win.yml`** holds the connection settings for the group: `winrm`, port 5986, user `Administrator`, NTLM transport, certificate validation `ignore` (self-signed, lab only), and `ansible_password` read from the environment variable `ANSIBLE_WIN_PASSWORD`. It contains no secret and is safe to commit.

### Troubleshooting: key pair not found

8. The first `apply` failed with `InvalidKeyPair.NotFound: The key pair 'terransi-winkey.pem' does not exist`. The value in `key_name` included `.pem`, which is part of the **file name**, not of the key pair name.
9. **Fix:** list the real names with `aws ec2 describe-key-pairs`, correct `terraform.tfvars`, check `terraform state list` (Terraform doesn't roll back, so the security group already existed), then plan and apply again.
10. **Hardening (optional):** an `aws_key_pair` data source makes `plan` fail early on a wrong name, and a `validation` block on the variable rejects a name ending in `.pem`. The lesson is the same as Day 3: `plan` can only catch what it can check.

---

## Part C — Connecting

11. **Port test** from PowerShell: `Test-NetConnection -Port 5986` returned `TcpTestSucceeded: True`.
12. **Password:** decrypted in the AWS console with the RSA `.pem` (4-10 minutes after launch), then typed into a **silent prompt** in WSL (`read -rs`), exported as `ANSIBLE_WIN_PASSWORD`. It lives only in that terminal session: not in a file, not in Git, not in the shell history.
13. **`win_ping`** returned `pong`. It isn't an ICMP ping: it logs in over WinRM and runs a small PowerShell module, so it proves the credentials, the certificate handling, and the transport.
14. **First look** with read-only commands. The disk list showed disk 0 (MBR, about 32 GB, the system disk) and disk 1 (RAW, 2 GB, not system).

---

## Part D — IIS playbook (`ansible/iis.yml`)

15. Tasks: install the `Web-Server` feature (with management tools), reboot only if `reboot_required`, start the `W3SVC` service (automatic start), open port 80 with `community.windows.win_firewall_rule`, and deploy `index.html`.
16. **First run:** IIS install, firewall rule and index page `changed`. **Second run:** everything `ok`, nothing to change.
17. Tested the page from PowerShell with `Invoke-WebRequest`.

---

## Part E — Data disk playbook (`ansible/data-disk.yml`)

18. **Selection by state, not number:** `win_disk_facts` reads all disks, the playbook keeps those that aren't the system disk, and an `assert` stops unless there is **exactly one** (it refuses to guess).
19. **Safe steps:** initialize as GPT only when the disk is RAW, partition with a fixed drive letter (`E`) using the whole disk, format NTFS (label `DATA`) without `force`, write the test file with `force: false`, then read the volume and file back.
20. **First run:** initialize, partition, format and the file task `changed`. **Second run:** everything `ok`, with only the initialize task `skipped` (the disk was no longer RAW), and the file's timestamp unchanged.
21. **Result:** drive E, NTFS, label `DATA`, size 2130636800 bytes, and the test file with its timestamp. The volume is about 16 MB smaller than the 2 GiB disk, most likely because of the small reserved partition Windows creates on GPT disks (`Get-Partition` shows it).

---

## Part F — Idempotency and drift

22. Changed the page by hand with `win_shell`, then ran `iis.yml` with **`--check --diff`**: only the page task showed `changed`, with the diff of the content, and nothing was modified.
23. Ran it for real, and the original page came back. Hand edits to a managed file get overwritten, so the change belongs in the playbook.
24. **Why no `--check` for the disk playbook:** check mode doesn't execute changes, but on a RAW disk the initialize and partition steps would only be simulated, so the format task would look for a drive that doesn't exist yet and the preview would be misleading.

---

## Part G — Optional baseline playbook (`ansible/baseline.yml`)

25. Registry marker (`win_regedit`), a machine environment variable (`win_environment`), the **Windows Server Backup** feature (`win_feature`, with a reboot only if required), and a read-only query of the IIS service state (`win_service_info`). It practices "install something" and "change something" with no external downloads.

---

## Part H — Teardown (leftovers script before and after)

26. **Before:** 1 running instance expected (the data volume is attached, so the unattached-volumes check doesn't list it).
27. **Destroyed** the stack: the plan listed 5 resources (instance, security group, data volume, attachment, inventory file). The instance is stopped first to detach the volume cleanly.
28. **After:** CLEAN, exit code 0 expected. Terraform created everything, so it removed everything, and there is nothing outside Terraform for the script to find.
29. **Cleared the password from the shell:** `unset ANSIBLE_WIN_PASSWORD` (and `deactivate` if a virtual environment was used). The state files in the S3 bucket stay.

---

*Result: a Windows Server built by Terraform and configured by Ansible over WinRM HTTPS, with the password kept out of every file, a disk prepared by state instead of number, idempotent runs, drift repaired and previewed, and a verified clean teardown.*
