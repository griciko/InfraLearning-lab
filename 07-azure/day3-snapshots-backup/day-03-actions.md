# Day 3: Actions (snapshots, restore, image, Azure Backup)

Date: 27 October 2026. Region: `belgiumcentral`. Folder: `07-azure\day3-snapshots-backup\` with two Terraform projects, `workload\` and `backup\` (state keys `day3-workload.tfstate` and `day3-backup.tfstate` in the existing `tfstate` container).

Only what the learner reported is recorded. Anything not reported is marked *not recorded*.

---

## Part A: Checks and preparation

- Created `workload\` and `backup\`, copied `terraform.tfvars` and `backend.tf` from Day 2, changed the `key` in each `backend.tf`.
- `Microsoft.RecoveryServices` provider: **Registered**. The location list for `vaults` **includes Belgium Central**.
- Public IP matched `my_ip`, the public key file exists (`Test-Path` = True).

## Part B: Workload project (Linux VM + 4 GB data disk)

- Resources: resource group `rg-tf-lab-day03`, VNet, subnet, NSG (SSH from my IP only), association, static public IP, NIC, Linux VM (`Standard_B2ats_v2`, Ubuntu 24.04), data disk `disk-data-01` (4 GB), disk attachment (LUN 0).
- `Plan: 10 to add`, `Apply complete! Resources: 10 added`.
- Formatted the new disk once (`mkfs.ext4`), mounted at `/data`, wrote `important.txt`: `important data v1 Tue Oct 27 15:35:53 UTC 2026`.
- Design: `restore_snapshot_id` variable. Empty = `create_option "Empty"`, set = `create_option "Copy"` with `source_resource_id`.

## Part C: Manual snapshot and restore (scenarios 1 and 2)

```powershell
az group create -n rg-lab-snapshots -l belgiumcentral
az group create -n rg-lab-restore   -l belgiumcentral
az snapshot create -g rg-lab-snapshots -n snap-data-v1 --source $diskId --location belgiumcentral
az disk create -g rg-lab-restore -n disk-restored-v1 --source $snapId --location belgiumcentral
az vm disk attach -g rg-tf-lab-day03 --vm-name vm-tf-lab-03 --name $restoredId --lun 1
```

- Snapshot `snap-data-v1`: 4 GB, **`Incremental: False`**, created 15:38:10 UTC.
- After the snapshot I changed `/data/important.txt` to `changed after the snapshot`.
- Restored disk mounted **read-only** at `/restore`: shows the v1 text. `/data` shows the changed text. No `mkfs` on the restored disk.
- Detached the restored disk, `terraform plan`: **No changes**.

## Part D: Snapshot managed by Terraform (scenario 3)

- Added `azurerm_snapshot.tf` (`create_option = "Copy"`, `source_uri` = the data disk). `Plan: 1 to add`, `Apply complete! Resources: 1 added`.
- `plan -destroy` listed `azurerm_snapshot.tf` (yes). The manual snapshot was not in the list.
- Removed the block again: `Plan: 0 to add, 0 to change, 1 to destroy`, `Destruction complete after 11s`.

## Part E: Simulated disaster and rebuild (scenario 4)

- First `plan`: No changes. Destroyed the whole workload (destroy output *not recorded*), `snap-data-v1` survived (it lives outside the project).
- Added `restore_snapshot_id = "<snapshot id>"` to `workload\terraform.tfvars`.
- Rebuild plan: `Plan: 10 to add`, disk showed `create_option = "Copy"` and a `source_resource_id`.
- Mounted without `mkfs`: `important data v1 Tue Oct 27 15:35:53 UTC 2026` (the original timestamp, not the "changed" text).

## Part F: Backup project

Resources: resource group `rg-tf-backup-day03`, Recovery Services vault `rsv-lab-day03` (Standard, LocallyRedundant), policy `policy-daily-7d` (daily at 23:00 UTC, 7 daily points kept), protected VM. The VM is read through a `data` source, so the backup project does not own it.

- Provider `features` block used: `recovery_service { vm_backup_stop_protection_and_retain_data_on_destroy = false, purge_protected_items_from_vault_on_destroy = true }`. `validate` accepted it.
- `validate` warnings and fixes:

| Warning | Fix |
|---|---|
| Undeclared variable `my_ip` (copied `terraform.tfvars`) | Deleted the `my_ip` line from `backup\terraform.tfvars` |
| `soft_delete_enabled` deprecated (soft delete is always on) | Deleted that line from the vault resource |

- `Plan: 4 to add`, `Apply complete! Resources: 4 added`.

## Part G: On-demand backup, restore and timed test

- RTO for the test: **30 minutes** (proposed in the plan, written before the test).
- Marker written before the backup: `backup test Tue Oct 27 18:03:48 UTC 2026`.
- Ran `az backup protection backup-now`, waited for the job (backup job duration *not recorded*, exact `backup-now` flags *not recorded*).
- Recovery points: **3 rows**. The one used: **2026-10-27 18:05:03 UTC** (names and consistency column *not recorded*).
- Staging storage account for the restore created in `rg-lab-restore` (name not recorded here on purpose).
- Restore job started at **19:50:50 UTC**. Age of the recovery point at restore: about **1 h 46 min**.

| Phase | Time | Note |
|---|---|---|
| Restore job, Azure's own duration | 0:01:06 | From `az backup job list` |
| Restore, stopwatch | 3:09 | `$t0` was set once and not restarted after the failed first attempt |
| Rebuild (attach disk) | 10:35 | Includes troubleshooting the disk lookup |
| Verify (read-only mount) | 0:53 | |
| **Total, stopwatch** | **14:37** | Upper bound. Under the 30-minute RTO even so |

- Restore created two disks in `rg-lab-restore`: `vmtflab03-datadisk-000-20261027-195123` (4 GB) and `vmtflab03-osdisk-20261027-195123` (30 GB, Linux).
- Settings Azure applied to the restored data disk: `Standard_LRS`, 4 GB, **no zone**, `EncryptionAtRestWithPlatformKey`, tags `day` and `project` copied from the source, plus a new tag `RSVaultBackup` (its value equals the restore job name).
- Attached the restored data disk as LUN 2, mounted **read-only**: both `backup-marker.txt` (18:03:48 text) and `important.txt` (v1 text) present.
- Detached the disk, `terraform plan` on the workload: **No changes**.

## Part H: Image from the VM (scenario 5)

```bash
sudo waagent -deprovision+user -force
```
```powershell
az vm deallocate -g rg-tf-lab-day03 -n vm-tf-lab-03
az vm generalize -g rg-tf-lab-day03 -n vm-tf-lab-03
$vmId = az vm show -g rg-tf-lab-day03 -n vm-tf-lab-03 --query id -o tsv
az image create -g rg-lab-restore -n img-lab-01 --source $vmId --hyper-v-generation V2
```

- Image `img-lab-01`: generation V2, OS state `Generalized`, **`dataDisks: []`** (OS disk only, cause *not determined*).

## Part I and J: Teardown and verification

1. Backup project: `plan -destroy` = 4, `Destroy complete! Resources: 4 destroyed`, vault list empty.
2. Workload project (sequence as reported):
   - `plan -destroy`: `Plan: 0 to add, 0 to change, 10 to destroy`.
   - `destroy` failed: 409 `OperationNotAllowed ... since the VM is generalized` while removing the data disk from the VM.
   - Ran `terraform state rm azurerm_virtual_machine_data_disk_attachment.data`, then `Plan: 0 to add, 0 to change, 7 to destroy`.
   - `destroy` failed again: 409 `OperationNotAllowed: Disk disk-data-01 is attached to VM` (while deleting the managed disk).
   - Waited 10-15 seconds, the plan then showed `2 to destroy`, and the destroy finished. The `az vm delete` fallback was not mentioned, so it is not recorded as used. The final `Destroy complete` line was not pasted.
3. `az group delete` for `rg-lab-restore` and `rg-lab-snapshots`.
4. Found an extra group **`AzureBackupRG_belgiumcentral_1`** containing a restore point collection `AzureBackup_vm-tf-lab-03_<id>`. Deleted the **collection first**, then the group.
5. Final state: `az group list` shows only `NetworkWatcherRG` and `rg-tfstate`. `az resource list` shows only `NetworkWatcher_belgiumcentral` and the state storage account. VM, snapshot, vault, disk and image lists are empty. `terraform state list` is empty in both projects.

## Errors and fixes

| What happened | Cause | Fix |
|---|---|---|
| `az vm disk attach`: `expected one argument` (twice) | `$d` was empty. First time the restore had not run yet, second time my size filter matched nothing (cause not confirmed, probably PowerShell quoting of the number) | Read the disk name from `az disk list -g rg-lab-restore`, use `az disk show ... --query id` |
| Same error on `restore-disks` | Command pasted as one line with backticks in the middle, `$job` was empty | One command per line, or all on one line without backticks. Check variables with `"[$var]"` |
| `ResourceNotFound` for the storage account in `rg-tf-backup-day03` | `restore-disks` looked in the vault's resource group | Pass the storage account **ID** (`az storage account show ... --query id`) |
| `az disk list` needs `-g` | This CLI version requires a resource group | Loop over `az group list` |
| `terraform destroy`: 409 `OperationNotAllowed ... since the VM is generalized` | Terraform has to update the VM to detach the data disk, and a generalized VM cannot be updated | Remove the attachment from state (`terraform state rm azurerm_virtual_machine_data_disk_attachment.data`) and destroy again |
| `terraform destroy`: second 409 `Disk disk-data-01 is attached to VM` | After `state rm`, Terraform tried to delete the disk while the VM still had it attached | Wait 10-15 seconds and run the destroy again (the plan then showed 2 resources left), it finished |
| Extra group `AzureBackupRG_belgiumcentral_1` not on the expected-leftovers list | Created automatically by Azure Backup for instant-restore snapshots (restore point collection) | Delete the collection, then the group |

## Cleanup checklist (all done)

- [x] Backup project destroyed, vault gone
- [x] Workload project destroyed
- [x] `rg-lab-restore`, `rg-lab-snapshots` deleted
- [x] `AzureBackupRG_belgiumcentral_1` deleted
- [x] Only `rg-tfstate` and `NetworkWatcherRG` remain

**Before reusing `workload\`:** `workload\terraform.tfvars` still contains `restore_snapshot_id`, which now points to a deleted snapshot. Remove that line first, or the next apply fails.

## Files to commit

`07-azure\day3-snapshots-backup\workload\`: `backend.tf`, `main.tf`, `variables.tf`, `outputs.tf`
`07-azure\day3-snapshots-backup\backup\`: `backend.tf`, `main.tf`, `variables.tf`
`07-azure\docs\`: `day-03-actions.md`, `day-03-learned.md`

Never commit `terraform.tfvars` (it contains the subscription ID and the snapshot ID).
