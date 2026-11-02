# Day 2: What I learned (remote state, Windows VM, Ansible over WinRM)

## Remote state in Azure Blob Storage

- **Bootstrap problem:** the state storage must exist before Terraform can use it, so it is created once with `az`, outside the project, in its own resource group (`rg-tfstate`). Same idea as the S3 bucket on AWS Day 3. It is kept for the whole training and deleted at the end.
- **Authentication:** with `use_azuread_auth = true` Terraform uses my Azure identity instead of a storage account key. This needs the role `Storage Blob Data Contributor` on the storage account, because being owner of the subscription is not the same as having data access to blobs. No shared secret has to be handled.
- **A backend block cannot use variables.** The storage account name is written out in the file. It is an identifier, not a secret.
- **Locking:** the azurerm backend locks the state with a blob lease. While one `apply` waited for `yes`, a second `plan` failed with `Error acquiring the state lock ... state blob is already locked`. Only one run at a time can work on the same state.
- **Versioning:** with blob versioning enabled on the storage account, every state write creates a new version. After one session the single blob had 20 versions, including several of identical size that most likely come from lock and unlock writes (as on S3).
- **Secrets end up in state.** The generated admin password was readable in plain text with `terraform state pull`. Whatever Terraform generates or receives is stored, so the state container must stay private with tight access.
- After `destroy`, the state blob stays in the container (empty). Deleting the resources does not delete the state.
- The state is remote, so there is no local `terraform.tfstate`. Only `.terraform/` (backend settings) stays on disk.

## Windows VM on Azure

- A Windows VM needs more memory than the 1 GiB Linux size from Day 1, so I used `Standard_B2s_v2` (2 vCPU, 8 GiB). The size is part of the price, so check it before `apply` and destroy at the end of the session.
- The admin user and password are set when the VM is created. There is no decryption step like the AWS Windows password retrieval. I let Terraform generate the password with `random_password`, and it is retrieved with `terraform output -raw admin_password`.
- **Hotpatch images need `patch_mode`.** The image `2025-datacenter-azure-edition` made the provider demand `patch_mode = "AutomaticByPlatform"`. `plan` passed and `apply` failed (third example of this pattern).
- A Windows computer name is limited to 15 characters, so the VM name and the `computer_name` are set separately.
- **Terraform did not roll back again.** After the failure, 9 resources existed, including `local_file.inventory`, written even though the VM was never created, because the file depends only on the public IP.
- After a fix, `plan` showed only `2 to add`: Terraform creates just what is missing.

## Ansible over WinRM

- WinRM (port 5985) with NTLM replaces SSH. The Terraform-to-Ansible handoff is again a file: `inventory.ini` with the IP, and the password is passed at run time with `-e ansible_password=...` and never written to the file.
- Windows modules use the `ansible.windows` collection (`win_ping`, `win_feature`, `win_copy`, `win_service`, `win_reboot`).
- **`--check` fails on service tasks for a fresh machine**, as on Linux: the dry run does not install the IIS feature, so the service does not exist yet. The real run worked.
- **Idempotency:** the first run changed things, the second run changed nothing. No reboot was needed.
- **Shell variables do not survive a new WSL session.** The warning `Unable to parse inventory` was misleading: Ansible said it could not parse the file, but the real cause was a wrong or empty `$path`. Check the path (`ls`) before assuming the file is broken, and set `path=...` again at the start of each WSL session, like `ssh-add`.

## Mistakes and fixes worth remembering

| What happened | Lesson |
|---|---|
| `apply` failed with `patch_mode must always be set to AutomaticByPlatform` | `plan` does not enforce every provider rule. Hotpatch images need `patch_mode`. Add the one missing line and rerun |
| `Unable to parse inventory` warning in Ansible | A wrong `$path` shows up as a parse warning. Verify the path with `ls` first |
| Failed `apply` left 9 of 11 resources | Run `terraform state list` after a failure. A rerun creates only what is missing |

## Production notes (lab vs. production)

- **WinRM over HTTP (5985) with NTLM** is a lab choice, restricted to my IP by the NSG. Production uses HTTPS (5986), a private network, a bastion or VPN, and no public management ports.
- **RDP from my IP** is acceptable for a lab. Production uses a bastion or just-in-time access.
- **A generated password in Terraform state** is a lab shortcut. Production keeps secrets in Key Vault and never in generated values in state.
- **State storage** was private with Azure AD roles. Production adds strict role separation, soft delete, locks against deletion and, for important states, protection against loss of the storage account.
- **One state file for one lab.** Production uses separate states per environment and per team.
- **Cost control:** manual destroy is acceptable for a lab. Production uses tagging, budgets, schedules and cleanup policies.

## Mapping file (`aws-azure-mapping.md`): updates after Day 2

| Open item | Status |
|---|---|
| `azurerm` backend locking and versioning details | **Confirmed**: lock through a blob lease (second `plan` blocked), versioning on the storage account (20 versions after one session) |
| Windows VM: password set at creation, no decryption | **Confirmed** with a Terraform-generated password |
| `plan` passes, `apply` fails on Azure | **Third example**: hotpatch `patch_mode` rule |
| Terraform with `azurerm` for a Windows VM | **Done** (`Standard_B2s_v2`, Server 2025 Azure Edition) |

## Open questions

- Which of the 20 state versions belong to which command? Compare timestamps with the command history if it matters.
- Does soft delete or versioning on the state storage cost anything noticeable over the training? Check Cost Management at the end.
- How does the extension-based WinRM setup compare with the default WinRM listener? Was the extension needed at all on this image?
- `az vm list-skus` showed restrictions on the sizes, while the portal's size picker lists these as usable in this subscription: Linux `Standard_B2ats_v2` and `Standard_B2als_v2`, Windows `Standard_B2ls_v2`, `Standard_B2as_v2` and `Standard_B2s_v2`. Which restriction did `az` show (zone only, as on Day 1, or the location)? Check the `Restrictions` details again before the next lab.
