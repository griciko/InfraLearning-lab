# Day 2: Actions (Windows VM, remote state in Blob Storage, Ansible over WinRM)

**Date:** 26 October 2026
**Working folder:** `D:\GITlabs\infra-learning-lab\07-azure\day2-windows-vm`
**Region:** `belgiumcentral`
**VM size:** `Standard_B2s_v2` (2 vCPU, 8 GiB)
**Image:** Windows Server 2025 Datacenter Azure Edition (`2025-datacenter-azure-edition`)

The plan for the day is in `day-02-plan.md`.

---

## 1. Preparation and remote state bootstrap

- Checked VM size and Windows image availability in `belgiumcentral`. The `az vm list-skus` output showed restrictions on the sizes, so I checked the portal's size picker directly. Sizes usable in this subscription according to the portal: **Linux** `Standard_B2ats_v2` and `Standard_B2als_v2`; **Windows** `Standard_B2ls_v2`, `Standard_B2as_v2` and `Standard_B2s_v2`. The raw `az` output was not recorded.
- Prepared WSL for Windows management (`pywinrm` and the `ansible.windows` collection).
- Created the state storage once with `az`, outside the project:
  - resource group `rg-tfstate` (kept for the whole training),
  - a Standard_LRS storage account (globally unique name, TLS 1.2, public blob access disabled, blob versioning enabled),
  - container `tfstate`,
  - role `Storage Blob Data Contributor` for my own user, so Terraform can use Azure AD authentication instead of an access key.
- Terraform backend in `backend.tf`: `azurerm` with `use_azuread_auth = true` and the key `day2-windows-vm.tfstate`. The storage account name is written out in the file (a backend block cannot use variables).

## 2. Terraform: Windows VM with remote state

Files in `day2-windows-vm\`: `backend.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars` (not committed), `iis.yml`.

Resources (11): resource group, VNet, subnet, NSG (RDP 3389, WinRM 5985 and HTTP 80, all from my IP only), NSG association, static Standard public IP, NIC, `random_password` for the admin password, Windows VM, WinRM extension, `inventory.ini` (`local_file`).

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

First plan: `Plan: 11 to add, 0 to change, 0 to destroy.`

### Error on the first `apply`

```
"patch_mode" must always be set to "AutomaticByPlatform" when "source_image_reference"
points to a hotpatch enabled image
```

- `plan` passed, `apply` failed (third example of this pattern, after Day 1's two).
- Terraform did not roll back. `terraform state list` showed 9 resources: resource group, VNet, subnet, NSG, NSG association, public IP, NIC, `random_password` and `local_file.inventory`. The VM and the extension were not created.
- The `inventory.ini` file had already been written, because it depends on the public IP and not on the VM.

Fix: one line in the `azurerm_windows_virtual_machine` block:

```hcl
  patch_mode = "AutomaticByPlatform"
```

Second plan: `Plan: 2 to add, 0 to change, 0 to destroy.` (the VM and the extension). The apply then succeeded.

Remote state check: the state is stored in the blob, with no local `terraform.tfstate` file.

## 3. RDP

RDP worked: connected as `azureadmin` and checked system settings, setup and disks.

## 4. Ansible over WinRM

Playbook `iis.yml`: installs the IIS feature (`Web-Server`), deploys `index.html`, makes sure `W3SVC` runs, and reboots if needed.

Problem: the first `win_ping` showed these warnings:

```
Unable to parse .../inventory.ini as an inventory source
No inventory was parsed, only implicit localhost is available
```

- `inventory.ini` existed and its content was correct (`[windows]`, the IP, and the `[windows:vars]` block with `ntlm`, port 5985, `http`).
- Both `ls` commands in WSL worked, so the cause was the `$path` variable of that WSL session. Reassigning `path=/mnt/d/GITlabs/infra-learning-lab/07-azure/day2-windows-vm` fixed it.

Results:

| Step | Result |
|---|---|
| 1. `win_ping` | `pong` |
| 2. `--check` (dry run) | Errors on the service task (the dry run cannot see a feature that is not installed yet) |
| 3. Real run | `changed` for the IIS install and the page, **no reboot needed** |
| 4. Second run | No changes (idempotent) |
| Test from outside (`Invoke-WebRequest`) | Status 200 |
| Browser | The page was visible |

Both repeat experiments worked as expected: after changing the text in the playbook only the page task changed, and after a manual edit of the page the playbook restored it. The `PLAY RECAP` lines were not pasted, only the summary above.

## 5. Remote state experiments

**F1: blobs in the container** (`az storage blob list ... --include v`): one blob, `day2-windows-vm.tfstate`, with **20 versions** at the end of the session. Sizes seen: 181 bytes (empty state), 2610 and 17571 bytes (after the first apply), 26131 and 26282 bytes (after the VM and extension were created). Several versions have the same size, which most likely come from lock and unlock writes. This mapping of versions to commands is an interpretation, not recorded fact.

**F2: locking.** While `terraform apply` waited for `yes` in one window, `terraform plan` in a second window failed:

```
Error acquiring the state lock
Error message: state blob is already locked
```

Answering `no` in the first window released the lock.

**F3: secrets in state.** `terraform state pull | Select-String "result"` showed the generated admin password in plain text.

## 6. Teardown and cleanup checklist (still to do)

- [x] `terraform plan -destroy`: `Plan: 0 to add, 0 to change, 11 to destroy.`
- [x] `terraform destroy`: `Destroy complete! Resources: 11 destroyed`
- [x] `az group list -o table`: only `rg-tfstate` and `NetworkWatcherRG` remain
- [ ] `az vm list -d -o table`: no VM (not reported, the empty group list already implies it)
- [x] The state blob stays in the container, empty. That is normal.

There is no auto-shutdown in this region, and a Windows VM bills more than yesterday's Linux VM, so do not leave it running.

## 7. Files to commit

- `backend.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `iis.yml`, and these day files.
- **Never commit:** `terraform.tfvars`, `.terraform/`, `inventory.ini`, the admin password, keys, `*.pem`.
