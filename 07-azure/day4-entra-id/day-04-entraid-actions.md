# Day 4, part 1: Actions (Entra ID as code: users, groups, Azure RBAC)

**Date:** 28 October 2026
**Folder:** `07-azure\day4-entra-id\`
**Plan:** `day4-1-EntraID.md`
**State:** remote, key `day4-entra.tfstate` (container `tfstate` in `rg-tfstate`)
**Note:** part 2 (Hyper-V VM factory) was done in another chat and has its own notes. These files cover part 1 only. Items I did not report back are marked *not recorded*.

---

## Goal

Create two test users and two groups with Terraform (`azuread`), give the groups Reader and Contributor on one test resource group (`azurerm`), prove the permissions by logging in as the users, look at drift and the Activity Log, then destroy everything and confirm that the existing hand-built tenant objects are untouched.

---

## Steps done

### Part 0: leftovers from Day 3

- Removed the stale `restore_snapshot_id` line from `day3-snapshots-backup\workload\terraform.tfvars` and committed the Day 3 files (without `terraform.tfvars`).
- `az group list` showed only `NetworkWatcherRG` and `rg-tfstate` at the start. *(The plan's expected state; the exact start output was not recorded.)*

### Part A: preparation and checks

```powershell
cd D:\GITlabs\infra-learning-lab\07-azure
mkdir day4-entra-id
cd day4-entra-id
Copy-Item ..\day3-snapshots-backup\backup\terraform.tfvars .
Copy-Item ..\day3-snapshots-backup\backup\backend.tf .
(Get-Content .\backend.tf) -replace 'day3-backup\.tfstate','day4-entra.tfstate' | Set-Content .\backend.tf
```

Checks and results:

| Check | Result |
|---|---|
| `*.onmicrosoft.com` initial domain exists and is the E5 trial tenant | Yes |
| Logged-in account is `adm.lab` | Yes |
| Entra roles of `adm.lab` | Global Administrator (plus membership of the company M365 group) |
| Azure roles of `adm.lab` | Owner and Storage Blob Data Contributor |
| Baseline before the lab | **5 users, 6 groups** |

Added `tenant_id` and `usage_location` to `terraform.tfvars` and removed the unused `my_ip` line (per the plan). `.gitignore` already covered `*.tfvars`, `*.tfstate`, `*.tfstate.*` and `.terraform/`.

### Part B: Terraform project

Created `variables.tf`, `main.tf` and `outputs.tf` with the code from the plan (`backend.tf` copied in Part A).

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

| Step | Result |
|---|---|
| `init` | Installed `hashicorp/azurerm v4.81.0`. The `azuread`, `random` versions and the backend message were *not recorded* |
| `validate` | `Success! The configuration is valid.` |
| `plan` | `Plan: 11 to add, 0 to change, 0 to destroy.` (2 random passwords, 2 users, 2 groups, 2 memberships, 1 resource group, 2 role assignments) |
| `apply` | `Apply complete! Resources: 11 added, 0 changed, 0 destroyed.` |

Objects created, all with the `tf` prefix: users `TF Reader` and `TF Operator`, groups `grp-tf-readers` and `grp-tf-operators`, resource group `rg-tf-lab-day04`.

### Part C: reading the permissions

CLI check of the two role assignments, then portal check: `rg-tf-lab-day04`, Access control (IAM), Check access.

| Test user | Role | Scope shown | Came from |
|---|---|---|---|
| TF Reader | Reader | This resource | `grp-tf-readers` |
| TF Operator | Contributor | This resource | `grp-tf-operators` |

### Part D: logging in as the test users

Used a separate Azure CLI config folder (`AZURE_CONFIG_DIR` in `%TEMP%`) so the `adm.lab` login stayed untouched. Credentials were read from `terraform output` into variables, never printed.

| Test | Result |
|---|---|
| Reader: `az group show` on `rg-tf-lab-day04` | Worked |
| Reader: `az network vnet create` | **Denied**: `AuthorizationFailed` for `Microsoft.Network/virtualNetworks/write` |
| Operator: `az network vnet create` | Worked |
| Operator: `az network vnet delete` | Worked |
| Login blocked, MFA prompt or Conditional Access message | **None** |
| After `az logout` and removing `AZURE_CONFIG_DIR` | `adm.lab` active again |

Sign-in logs (Entra ID, Monitoring, Sign-in logs, tab Report-only) for a TF user:

| Policy | Result shown |
|---|---|
| `CA001-RequireMFA-AllUsers` (report-only) | User action required |
| `CA003-BlockLegacyAuth` (report-only) | Not applied |
| `CA002-RequireCompliantDevice-Pilot` | *not recorded* (it targets the pilot group, which the TF users are not in) |

### Part E: custom role

**Skipped** (optional). Moved to a quiet slot.

### Part F: drift and the Activity Log

| Experiment | What I did | Result |
|---|---|---|
| F1: change made by hand in Entra | Added `TF Operator` to `grp-tf-readers` in the portal, then `terraform plan` | `No changes. Your infrastructure matches the configuration.` The member was then removed by hand again *(removal not explicitly confirmed)* |
| F2: change Terraform can see | Deleted the Reader role assignment with `az role assignment delete`, then `terraform plan` | `Plan: 1 to add, 0 to change, 0 to destroy.` Then `terraform apply` restored it (the `write` event below is that restore; the apply output itself was *not recorded*) |
| F3: Activity Log | `az monitor activity-log list` on `rg-tf-lab-day04`, filtered in PowerShell | See below |

Activity Log events, all with caller `adm.lab`:

| Time (local) | Operation | Status |
|---|---|---|
| 12:13:03 | `Microsoft.Authorization/roleAssignments/delete` | Started |
| 12:13:04 | `Microsoft.Authorization/roleAssignments/delete` | Succeeded |
| 12:16:54 | `Microsoft.Authorization/roleAssignments/write` | Started |
| 12:16:56 | `Microsoft.Authorization/roleAssignments/write` | Succeeded |

How long the events took to appear in the log: *not recorded*. Which tool made the call (CLI or Terraform): not identified, see the learned file.

### Part G: teardown and verification

```powershell
terraform plan -destroy
terraform destroy
```

| Check | Result |
|---|---|
| `terraform destroy` | `Destroy complete! Resources: 11 destroyed.` |
| `rg-tf-lab-day04` | Gone |
| Users named `TF *`, groups named `grp-tf-*` | None left |
| Users and groups count | **5 and 6** (equal to the baseline) |
| Entra recycle bin | The deleted `TF` users are listed |
| `az group list` | Only `NetworkWatcherRG` and `rg-tfstate` |

**G2, rebuild while the old users sit in the recycle bin:** `terraform apply` created 11 resources and `terraform destroy` removed 11 again, with no errors and no name conflict.

---

## Errors and fixes

| What happened | Fix |
|---|---|
| `az ad user list --query "length(@)"` failed with `invalid jmespath_type value: 'length(@'` | On Windows `az` is a batch file and the closing `)` is lost. Count in PowerShell instead: `az ad user list --query "[].id" -o tsv \| Measure-Object \| Select-Object -ExpandProperty Count` |
| The `AuthorizationFailed` message was pasted with the full sign-in name and tenant domain | Harmless here. Next time replace names and IDs with placeholders before pasting |

---

## Cleanup checklist (done)

- [x] `terraform destroy` of the Day 4 Entra project (11 resources, twice)
- [x] `rg-tf-lab-day04` gone
- [x] No `TF` users, no `grp-tf-*` groups
- [x] 5 users and 6 groups (baseline)
- [x] Only `NetworkWatcherRG` and `rg-tfstate` left
- [x] `AZURE_CONFIG_DIR` removed, `adm.lab` active
- [x] Files committed (not recorded which exactly: see below)

Note: the TF users still sit in the Entra recycle bin. Deleted users are kept for 30 days and clear by themselves (nothing to do).

---

## Files to commit

In `07-azure\day4-entra-id\`: `backend.tf`, `main.tf`, `variables.tf`, `outputs.tf`.
**Never commit:** `terraform.tfvars` (subscription and tenant ID), `.terraform\`, any state file.
