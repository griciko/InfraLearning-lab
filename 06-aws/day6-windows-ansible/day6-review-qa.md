# Day 6 — Review Q&A

Review notes for Day 6: Ansible on Windows over WinRM, with Terraform building the server.

**Lab vs. production:** all of this is lab work. The tables at the end say where real environments differ.

---

## A. Review questions

### 1. Terraform generated `inventory.ini` and `group_vars/win.yml` holds the connection settings. Where does the password come from, and why isn't it in either file?

The password was decrypted in the AWS console with the RSA `.pem` key and typed into a silent prompt in WSL. It exists only as an environment variable (`ANSIBLE_WIN_PASSWORD`) in that terminal session, and `group_vars/win.yml` only contains a lookup of that variable. It isn't in any file for three reasons: files can end up in Git or backups, a silent prompt keeps it out of the shell history, and the password is random per instance, so a stored copy would be stale after the next launch anyway. In production the password would come from a secrets store or Ansible Vault.

### 2. Why HTTPS on port 5986 with NTLM, and which two things made this setup lab-only?

Port 5986 is WinRM over **HTTPS** (5985 is plain HTTP), so the channel is protected. NTLM is used because Administrator is a **local** account, while Kerberos would require a domain. Two things made it lab-only: the **self-signed certificate with validation turned off** (`ansible_winrm_server_cert_validation: ignore`), and **WinRM reachable from the internet**, narrowed only by the security group to one IP. Also lab-style: the local Administrator with a hand-typed password, and an inline user-data script instead of a prepared image. Production uses a trusted certificate with validation on, no direct internet exposure (VPN, bastion, or managed access), domain or dedicated automation accounts with Kerberos, and a secrets store.

### 3. How does the disk playbook find the data disk without a hardcoded number, what stops it from touching the wrong disk, and why is the second run safe?

The playbook reads all disks with `win_disk_facts` and selects by **state**: every disk that isn't the system disk is a candidate. It doesn't use the disk number (not a fixed identity, the same trap as `nvme1n1` on Linux) and, unlike Day 5, not an ID either. Several guards keep it from touching the wrong disk: an `assert` stops the run unless there is exactly one non-system disk (it refuses to guess), initialization only happens when the disk is RAW, the partition has a fixed drive letter, `win_format` has no `force` so an existing filesystem is never overwritten, and the test file is written with `force: false`. The second run is safe because of those guards: the disk isn't RAW any more so initialize is skipped, the partition and volume already match, and the file already exists. "Any non-system disk" is a lab shortcut: with several data disks you'd select by unique ID, serial number, or size.

### 4. What's the difference between `ok`, `changed`, and `skipped`, and what did the skipped initialize task tell you?

`ok` means the task ran, checked, and found nothing to change. `changed` means the task made a change. `skipped` means its `when` condition was false, so the task did not run at all, which is different from `ok`. The initialize task was skipped on the second run because the disk was no longer RAW. The same applies to "Reboot if required": skipped means Windows reported that no reboot was needed.

### 5. Why was `--check --diff` a good preview for the IIS playbook, and why was it not suggested for the disk playbook?

For IIS, check mode showed exactly which task would change (only the index page) and the diff of the content, while changing nothing, the Ansible counterpart of `terraform plan` and PowerShell's `-WhatIf`. For the disk playbook, the concern isn't data loss: check mode doesn't execute changes (modules that can't simulate one are skipped), and `win_format` without `force` never overwrites an existing filesystem anyway. The real problem is a **misleading preview**: on a RAW disk, initialize and partition are only simulated, so the format task would look for a drive letter that doesn't exist yet and fail or mislead.

---

## B. Troubleshooting notes

| Problem | Cause | Fix and lesson |
|---|---|---|
| `InvalidKeyPair.NotFound: 'terransi-winkey.pem'` on apply | `.pem` is part of the file name, not the key pair name | Use the name from `aws ec2 describe-key-pairs`. Terraform doesn't roll back: `terraform state list` showed what already existed. A data source plus a `validation` block can make this fail at plan time |
| Wrong collection assumed for the firewall module | `win_firewall_rule` is in `community.windows`, not `ansible.windows` | Check with `ansible-doc -l | grep win_` and `ansible-doc <module>` instead of assuming |
| User-data script changes don't apply to a running instance | The script only runs at first boot | `user_data_replace_on_change = true`, so a changed script replaces the instance |

---

## C. What else Ansible can do on Windows

| Task | Typical module |
|---|---|
| Install software | `win_package`, Chocolatey (separate collection) |
| Roles and features | `win_feature`, `win_optional_feature` |
| Windows updates | `win_updates` with `win_reboot` (one server at a time with `serial: 1`) |
| Settings | `win_regedit`, `win_environment`, `win_path`, `win_hostname` |
| Users and groups | `win_user`, `win_group_membership` |
| Services, firewall, shares | `win_service`, `win_firewall_rule`, `win_share` |
| Run PowerShell | `win_powershell`, `win_shell` (not idempotent unless guarded) |
| DSC | `win_dsc` |
| Reports without changes | `--check`, `win_service_info`, `win_reg_stat`, `win_stat` |

GPO and Intune manage users and devices, and Ansible is strongest for server configuration and repeatable procedures across many machines, so they complement each other.

---

## D. Lab vs. production: Day 6

| Topic | In the lab | In production |
|---|---|---|
| WinRM exposure | Open to my IP only | Not exposed to the internet: VPN, bastion, or managed access |
| Certificate | Self-signed, validation off | Trusted certificate, validation on |
| Account | Local Administrator with NTLM | Domain or dedicated automation accounts, Kerberos |
| Password | Typed into a silent prompt, kept in an environment variable | Secrets store or Ansible Vault |
| WinRM setup | Inline user-data script at first boot | Prepared image (for example Packer) or managed configuration |
| Disk selection | The only non-system disk | By unique ID, serial number, or size |
| Playbooks | Single files run by hand | Roles, inventories per environment, run from a pipeline or an automation platform |
| Verification | A few read-only checks | Check-mode compliance reports, results logged |
| Patching | Not done | Orchestrated, one server at a time, with reboots and verification |

---

## E. How to explain this in an interview

> "I used Terraform to build a Windows Server on AWS and Ansible over WinRM HTTPS to configure it: roles and services, firewall rules, data disk preparation that selects the disk by state and refuses to guess, and a registry and environment baseline. Runs are idempotent, drift gets repaired, and check mode previews the changes. The password stayed out of every file. This is lab work: in production I'd use a trusted certificate, no internet exposure for WinRM, Kerberos with domain accounts, and a secrets store."

Every point in that is something that was actually run in the lab.

---

*Day 6 covered: enabling WinRM over HTTPS at first boot, a connection group with the password from the environment, `win_ping` and read-only inspection, IIS, firewall and service management, safe disk preparation by state with guards, idempotency and drift with check mode, an optional baseline, and a verified clean teardown.*
