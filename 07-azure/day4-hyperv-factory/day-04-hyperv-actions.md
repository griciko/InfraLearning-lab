# Day 4: Actions (part 2: Hyper-V VM factory)

Folder: `07-azure\day4-hyperv-factory\`. Host: `TC-WIN-DC01.main.local` (Windows Server 2025, Hyper-V, domain `MAIN`).

**Scope of this file:** part 2 only (Hyper-V VM factory). Part 1 (Entra ID, `day4-entra-id`) is **not recorded here**: no results were reported for it in this session.

**Goal:** build a reusable Windows 11 base disk on the host, create VMs from it with PowerShell (differencing disk, vTPM, Secure Boot), configure them with Ansible over WinRM, repeat with Terraform, and tear everything down except the existing lab VM and the base disk.

---

## Part A: Connect to the host

| Step | Result |
|---|---|
| Host type | Domain controller, so there are no local accounts. A **domain administrator** (`MAIN\...`) is used |
| `New-PSSession` by host name | Failed: `0x8009030e`, "A specified logon session does not exist". The workstation is not joined to `main.local`, so Kerberos was not possible and NTLM needs `TrustedHosts` |
| `Set-Item WSMan:\localhost\Client\TrustedHosts` | First attempt: `Access is denied` (PowerShell was not elevated). Worked in an **administrator** window |
| `New-PSSession` again | Worked. `hostname` returned `tc-win-dc01`, the `Hyper-V` module was present |
| Folders created on the host | `C:\Temp\lab`, `D:\HypVMs\tf-images`, `D:\HypVMs\tf-vms` |

## Part B: Read-only recon

| Item | Result |
|---|---|
| Existing VM | `W11-LAB01`, Off, generation 2, path `D:\HypVMs\W11-LAB01` (not touched all day) |
| Virtual switch used | `Intel(R) Ethernet Connection (2) I219-LM - Virtual Switch` |
| Free disk space on `D:` | 268.9 GB free, 107.9 GB used |
| Memory on the host | 15.7 GB total, 9.9 GB free |
| ISO | `D:\ISOtools\Win11t.iso` (on the host) |
| ISO edition used | Windows 11 Pro, `ImageIndex 1` |

Note: `Test-Path D:\ISOtools\...` checks the host's `D:` only when it runs **inside** `Invoke-Command -Session $s`. Typed alone it checks the workstation.

## Part C: Base disk

- Credential for the guest admin (`labadmin`) generated locally and stored with `Export-Clixml` outside the repo.
- Script run on the host. The copy used was `D:\HypVMs\scripts\LabBaseImage.ps1` (the plan said `C:\Temp\lab\`).
- Run time: **under 10 minutes**.
- Output: image file `E:\sources\install.wim`, boot partition `F:`, Windows partition `G:`, image index 1 applied, `Boot files successfully created`, `Answer file written`.
- Result: `D:\HypVMs\tf-images\win11-base.vhdx`, VhdType `Dynamic`, size 68,719,476,736 bytes (64 GB), file size 14,835,253,248 bytes (about 13.8 GiB).
- A `Get-VHD` on `tf-w11-01.vhdx` before the VM existed gave "not an existing virtual hard disk file". Expected, the child disk is created in Part D.
- Read-only check on the base disk: not recorded.

## Part D: First VM with PowerShell

- Script `New-LabVm.ps1` run on the host: VM `tf-w11-01`, generation 2, differencing disk from the base disk.
- `TpmEnabled: True`, `VhdType: Differencing`.
- First boot to a reachable VM: about **2 minutes**. The console first showed the "This might take a few minutes" screen (first-run setup).
- `Test-NetConnection <vm-ip> -Port 5985`: `TcpTestSucceeded True`.
- Differencing disk size: not recorded.

## Part E: Ansible over WinRM (script VM)

- Inventory: VM IP, user `labadmin`, `ansible_connection=winrm`, NTLM, port 5985, HTTP. Password passed with `-e` from an environment variable.
- `win_ping`: `pong`.
- Playbook `w11.yml` (rename, folder, file, hardware check):

| Run | PLAY RECAP |
|---|---|
| 1 | `ok=7 changed=4 unreachable=0 failed=0 skipped=0` |
| 2 | `ok=6 changed=0 unreachable=0 failed=0 skipped=1` |

- Hardware check: `SecureBoot true`, `TpmPresent true`, `TpmReady true`.
- Password experiment (count of `PlainText` entries in `C:\Windows\Panther\unattend.xml` in the guest): **0**.

## Part F: Same VM with Terraform

- Provider: `taliesins/hyperv`. Gate F0: the documentation for `hyperv_machine_instance` has **no TPM argument**.
- `terraform plan`: **`Plan: 2 to add, 0 to change, 0 to destroy`** (`hyperv_vhd.os` and `hyperv_machine_instance.w11`).
- First `apply` failed on the disk:

```
hyperv_vhd.os: Creating...
Error: checking for existing D:\HypVMs\tf-vms\tf-w11-02.vhdx: error uploading shell script: http response error: 401 - invalid content type
```

- Fix used: the WinRM service on the host was set to accept unencrypted traffic (`winrm set winrm/config/service '@{AllowUnencrypted="true"}'`). After that `apply` worked. This is a lab shortcut (see the learned file).
- Result: `hyperv_vhd.os` created after 24 s, `hyperv_machine_instance.w11` created after 3 m 2 s (id `tf-w11-02`), `Apply complete! Resources: 2 added, 0 changed, 0 destroyed`. Total about **3 m 26 s**.
- The VM has **no vTPM** (not possible with this provider).
- Ansible on the Terraform VM (new IP in `inventory.ini`, same playbook, renamed the VM):

| Run | PLAY RECAP |
|---|---|
| 1 | `ok=7 changed=4 unreachable=0 failed=0 skipped=0` |
| 2 | `ok=6 changed=0 unreachable=0 failed=0 skipped=1` |

## Part G: Teardown and verify

- `terraform destroy` for the Terraform VM, then the script VM `tf-w11-01` removed with `Stop-VM -TurnOff`, `Remove-VM` and removal of its folder.
- Destroy count reported by Terraform: not recorded (the plan expected 2).
- Verify: nothing left except **`W11-LAB01`** and the base disk **`D:\HypVMs\tf-images\win11-base.vhdx`** (kept for the Intune days).
- Helper files removed from the host, PowerShell sessions closed, the host credentials and `HYPERV_USER`/`HYPERV_PASSWORD` variables removed.

---

## Errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `0x8009030e` on `New-PSSession` | Workstation not in the domain, so no Kerberos | Add the host name to `TrustedHosts`, use `MAIN\user` |
| `Access is denied` on `Set-Item ...TrustedHosts` | PowerShell not elevated | Run as administrator |
| `Get-VHD` "not an existing virtual hard disk file" | Child disk not created yet | Expected, build the VM first |
| `401 - invalid content type` from `terraform apply` | Provider WinRM transport (cause not fully determined) | Lab workaround on the host, see Part F |

## Cleanup checklist

- [x] `tf-w11-01` and `tf-w11-02` removed, `D:\HypVMs\tf-vms` empty
- [x] Only `W11-LAB01` and the base disk remain
- [x] `C:\Temp\lab` removed from the host
- [x] Sessions closed, credential variables removed
- [ ] Optional: remove the `TrustedHosts` entry on the workstation when the Hyper-V work is finished

## Files to commit

- `New-LabBaseImage.ps1` (the host copy is `LabBaseImage.ps1`), `New-LabVm.ps1`, `w11.yml`
- The Terraform files of Part F
- **Not** `terraform.tfvars`, `inventory.ini`, the credential file, or anything with a password
