# Day 4: What I learned (part 2: Hyper-V VM factory)

Part 1 (Entra ID) is **not recorded here**: no results were reported for it in this session.

## Remoting to a Hyper-V host

- The host is a **domain controller**, so there are no local accounts. Remoting needs a domain admin in the form `MAIN\user`.
- From a workstation that is **not domain-joined**, Kerberos is not possible. `New-PSSession` then fails with `0x8009030e` unless the host name is in `TrustedHosts` (NTLM). Editing `TrustedHosts` needs an **elevated** PowerShell.
- `Invoke-Command -Session $s` runs on the **host**. A path like `D:\ISOtools\...` means the host's `D:` only inside the script block. The same command typed alone checks the workstation.
- `Copy-Item -ToSession` moves a script to the host without a share.
- Read-only recon first (VMs, switch, disk, RAM, ISO editions) avoided any change to the existing lab. Rule kept all day: create only `tf`-named objects, never touch `W11-LAB01`.

## Base disk and VM factory

- A **base VHDX** built from the ISO (apply image, `bcdboot`, answer file) takes under 10 minutes. It is a 64 GB dynamic disk of about 13.8 GiB on disk.
- A VM built on a **differencing disk** boots from the parent without copying it. The first boot to a reachable VM took about 2 minutes, mostly first-run setup ("This might take a few minutes").
- Generation 2 with a **vTPM and Secure Boot** works from PowerShell: `TpmEnabled True`, and in the guest `TpmPresent`, `TpmReady` and `SecureBoot` were all true. This is what Intune and Defender labs need later.
- The base disk is a template, like an image or AMI: **never boot it, never join it to anything**.
- The answer file lets the first boot finish with no clicks (autologon, WinRM enabled by first-logon commands). After first boot, the guest had no `PlainText` entry in `Panther\unattend.xml` (count 0). The base disk itself was never booted, so its unprocessed answer file most likely still holds the admin password. Treat the base disk as a secret and never share it (inference, not tested).

## Ansible over WinRM

- Same pattern as Day 2: inventory with the VM IP, NTLM, port 5985, password passed at run time with `-e`.
- Idempotent again: run 1 `changed=4`, run 2 `changed=0` with the reboot task skipped.
- A playbook can also **report facts** (TPM, Secure Boot), not only change things. It is a useful check that a VM matches what a lab needs.

## Terraform with the Hyper-V provider

- `taliesins/hyperv` can create the VHD and the VM (`Plan: 2 to add`, apply in about 3 m 26 s), but its documentation has **no TPM argument**. A VM that needs a vTPM is built with PowerShell. Terraform cannot give that VM a TPM.
- The first `apply` failed with `401 - invalid content type` when uploading a shell script. It passed after the host's WinRM service was set to accept unencrypted traffic. The root cause was **not determined**. That setting is a **lab shortcut** and weakens the host.
- Same lesson as Azure: `plan` passed and `apply` failed, because `plan` cannot test the remote connection.
- After the apply, the new VM got a new IP, so `inventory.ini` was edited by hand. This is the same Terraform-to-Ansible handoff as on Days 1-3, here done manually.

## Mistakes and fixes

| What happened | Lesson |
|---|---|
| `0x8009030e` on `New-PSSession` | Not domain-joined means no Kerberos. Use `TrustedHosts` and `MAIN\user` |
| `TrustedHosts` edit gave `Access is denied` | Needs an administrator window |
| `Test-Path` on a host path from the workstation looks wrong | It only checks the host inside `Invoke-Command` |
| `Get-VHD` of a child disk before the VM existed failed | Expected, check order of steps |
| Terraform `401 - invalid content type` | Provider's WinRM transport. Used a lab workaround, cause not determined |
| Base script kept on the host as `D:\HypVMs\scripts\LabBaseImage.ps1`, not in `C:\Temp\lab` | Fine, but it is not a `tf` object and not in the repo. Commit the workstation copy |

## Production notes (lab vs. production)

- **WinRM:** the lab uses HTTP (5985), NTLM and an unencrypted workaround. Production uses **WinRM over HTTPS (5986) with a certificate**, or Kerberos inside a domain.
- **TrustedHosts:** a lab shortcut for a non-domain workstation. Production machines are domain-joined or use HTTPS with trusted certificates.
- **Admin account:** a domain admin on a domain controller that also runs Hyper-V is a lab setup. Production separates the hypervisor from the DC and uses a delegated account for Hyper-V.
- **Passwords:** the guest admin password lives in a local credential file (`Export-Clixml`, only readable by the same Windows user) and in the base disk's answer file. Production uses a secrets store and has no plain passwords in answer files.
- **Images:** the base disk is built by script. Production builds and patches images in a pipeline and versions them.
- **State:** this part used a script and a Terraform project against a single host. Production tracks VMs in code with remote state, and handles the hypervisor in a managed platform (SCVMM, Azure Local, or similar).
- **Cleanup:** manual teardown with `tf`-prefixed names is a lab habit. Production uses tags and policies.

## Mapping file (`aws-azure-mapping.md`): updates after Day 4 part 2

No item in section 7 changed today: the Hyper-V work sits outside the AWS/Azure mapping. Suggested new section for the file (**loose** mappings):

| Hyper-V (local lab) | Azure | AWS | Mapping |
|---|---|---|---|
| Base VHDX | Managed image / Compute Gallery image | AMI | Maps loosely |
| Differencing disk | Disk created from an image (full copy) | Volume from an AMI snapshot | Maps loosely |
| Virtual switch | VNet | VPC | Maps loosely |
| vTPM, Secure Boot (Gen 2) | Trusted launch | Nitro TPM | Maps loosely, *verify* |
| `taliesins/hyperv` provider | `azurerm` | `aws` | Maps in purpose, the Hyper-V provider is much less complete (no TPM argument) |

## Open questions

- What exactly causes the `401 - invalid content type` with the Hyper-V provider over WinRM? Is there a setup with HTTPS (5986) that avoids the unencrypted workaround?
- Can the provider set a vTPM in a newer version, or is a post-step with PowerShell the only way?
- Is the admin password really still in the base disk's answer file, and should the base disk be rebuilt without it before it is reused?
- Is the base disk read-only (the check was not recorded)?
- Part 1 (Entra ID): results not recorded.
