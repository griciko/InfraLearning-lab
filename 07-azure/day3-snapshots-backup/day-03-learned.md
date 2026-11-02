# Day 3: What I learned (snapshots, restore, image, Azure Backup)

## Snapshots and disks

- A **managed disk snapshot** is a copy of one disk, independent of the disk and of the VM. It survived destroying the whole workload and rebuilt the data disk with the original content.
- `az snapshot create` made a **full** snapshot (`Incremental: False`). On AWS, EBS snapshots are always incremental. In Azure incremental is an option.
- A snapshot inside the Terraform project **shares its lifecycle**: `plan -destroy` listed it. The manual snapshot in its own resource group was never touched. Keep recovery data outside the project that it protects.
- Restore from a snapshot: `create_option = "Copy"` with `source_resource_id` on the disk. A `restore_snapshot_id` variable (empty = `Empty`) turned the disaster rebuild into one added line.
- **Never `mkfs` a restored disk.** Mount it read-only to verify, so a failed restore cannot be hidden by a recreated file.
- Defaults differ: `az disk create` from a snapshot gave **Premium_LRS**, while the Azure Backup restore kept **Standard_LRS** (same as the source).
- A disk in another resource group must be attached by its **full ID**, not by name.

## Azure Backup

- Belgium Central supports Recovery Services vaults, a daily policy and VM protection. The VM had no zone set, so the zone restrictions from Day 1 did not matter.
- Vault, policy and protected VM live in a **separate project** with its own state. The VM is only read with a `data` source. Backups do not share a lifecycle with what they protect.
- **Soft delete is always on by default** now. The `soft_delete_enabled` argument is deprecated (removed in provider 5.0).
- The provider's `features { recovery_service { ... } }` block controls what `destroy` does with protected items. With `purge_protected_items_from_vault_on_destroy = true` and `vm_backup_stop_protection_and_retain_data_on_destroy = false`, the vault destroyed cleanly in one step. **Not tested without these settings.**
- A restore job creates resources **outside Terraform** (an OS disk and a data disk in the target resource group). The unused 30 GB OS disk still costs money until deleted.
- What the restore applied to the data disk: same type as the source (`Standard_LRS`), 4 GB, no zone, platform-key encryption, tags copied, and an extra `RSVaultBackup` tag.
- `restore-disks` needs a staging storage account. Given by name it was searched in the vault's resource group, so the **resource ID** is the safe form.
- **Azure Backup creates its own resource group** (`AzureBackupRG_<geo>_<number>`) holding a hidden **restore point collection** for instant-restore snapshots. It was not removed by `terraform destroy` of the vault project and it can cost money while restore points exist. I deleted the collection first, then the group.
- The job's own duration (1:06) is much smaller than a stopwatch around the CLI commands (3:09). Measure restore, rebuild and verify separately, and **restart the stopwatch after a failed attempt**.
- RPO: a daily policy means up to 24 hours of data loss in the worst case. The recovery point used was about 1 h 46 min old at restore.

## Images and generalization

- An image is a template for **new** VMs, different from a snapshot (one disk) and a backup (recovery points in a vault).
- `waagent -deprovision+user` wipes the identity, SSH host keys and the admin user, then `deallocate` and `generalize`. The VM is no longer usable.
- The image came out with **only the OS disk** (`dataDisks: []`). A VM built from it would start with an empty `/data`. Cause not determined.
- **A generalized VM cannot be updated**, so `terraform destroy` failed with a 409 when it tried to detach the data disk. Removing the attachment from state got past that, but the next destroy hit a second 409 (the disk was still attached to the VM when Terraform tried to delete it). After waiting 10-15 seconds the destroy finished. Never generalize a VM that Terraform manages. Build images from a throwaway VM, or with a tool such as Packer.

## CLI and PowerShell gotchas

- A backtick continues a line only when it is the **last character**. Pasted into the middle of a line it breaks the command.
- Print a variable with `"[$var]"` before using it. Empty variables produce `expected one argument` errors.
- Variables are lost when the window closes. Timers (`$t0`) too.
- This CLI version requires `-g` for `az disk list` and `az image list`. Loop over `az group list`.
- A numeric filter inside `--query` is easy to get wrong in PowerShell (my size filter returned nothing). Prefer exact names.

## Mistakes and fixes

| What happened | Lesson |
|---|---|
| `$d` empty, attach failed | Check the variable first, and use exact names or IDs |
| Restore command pasted as one line with backticks | One command per line |
| Storage account not found in the vault's resource group | Pass the resource ID |
| Generalized the VM, then `destroy` returned 409 | Generalizing is a one-way step that breaks Terraform management |
| `AzureBackupRG_belgiumcentral_1` was not on my expected-leftovers list | Backup creates hidden resources in a group of its own. Add it to the leftovers check |
| Stopwatch not restarted after an error | Totals become upper bounds. Record that honestly |

## Production notes (lab vs. production)

- **Backups:** I ran an on-demand backup and one restore test. Production uses the schedule, a **locked or immutable vault**, cross-region or cross-account copies and alerts on failed backup jobs.
- **Retention of data on destroy:** the lab setting purges backup data when the VM is destroyed. Production usually keeps it.
- **Restore testing:** done once, by hand. Production tests restores on a schedule and compares the measured time with the RTO.
- **Restores outside IaC:** the restored disk was not in Terraform. In production, adopt it (import) or replace it with a Terraform-built disk.
- **Images:** production builds images in a pipeline (for example Packer), never from a VM that is part of live infrastructure.
- **Terraform and cleanup:** cost control is still manual. Production uses tagging, budgets and cleanup policies, and its leftover checks know about service-created groups such as `AzureBackupRG_*`.

## Mapping file (`aws-azure-mapping.md`): updates after Day 3

| Open item | Status |
|---|---|
| Exact `azurerm` arguments for snapshots, disks, backup resources | **Done.** Worked: `azurerm_managed_disk` (`create_option = "Copy"`, `source_resource_id`), `azurerm_snapshot`, `azurerm_virtual_machine_data_disk_attachment`, `azurerm_recovery_services_vault`, `azurerm_backup_policy_vm`, `azurerm_backup_protected_vm`. `soft_delete_enabled` is deprecated |
| Which settings an Azure restore applies by default | **Confirmed** for a Linux data disk: same SKU as the source, size 4 GB, no zone, platform-key encryption, tags copied, extra `RSVaultBackup` tag |
| Zone restrictions or Belgium Central limiting Backup | **Backup works** in Belgium Central (vault, policy, protection, restore). Site Recovery and Defender features not tested |
| Soft-delete behavior when tearing down a vault | **Partly:** vault destroyed cleanly with the purge setting. Behavior without it, and soft-deleted data afterwards, not tested |
| "Replace existing" restore limits | Not tested |
| Whether the first scheduled Azure backup protects the VM | **Still open.** Only an on-demand backup was run. The 23:00 UTC schedule never ran before the teardown |
| Azure Policy options to enrol VMs in backup automatically | Not tested |
| Activity Log: which identity deleted a resource | Not tested |
| Auto-shutdown in Belgium Central | Not tested |

Scenario table (section 2.3): scenarios 1 to 5 and 7 are **done on Azure**. Scenario 6 is done with an on-demand backup and a timed restore, but the schedule was not exercised (same gap as AWS). New row for section 2.6: *a backup service may create its own hidden resource group, check for it in the leftovers check.*

## Open questions

- Why did the image contain no data disk?
- Does the 23:00 UTC scheduled backup really run and protect the VM?
- What exactly happens at vault destroy without the purge setting (soft-deleted data, retention)?
- Is the `AzureBackupRG_*` group always cleaned up when the vault is destroyed, or only after the collection is deleted by hand?
- Does "Replace existing" restore work for this VM type?
