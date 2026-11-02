# Day 1: What I learned (Azure, Terraform, Ansible)

## Azure basics

- A **resource group** is the unit of lifecycle: everything inside it can be deleted with one command. Deleting only the VM leaves the disk, NIC, public IP and NSG behind, and they keep costing money.
- A VM is several resources, not one: virtual network, subnet, NSG, public IP, NIC, disk, VM. In the portal the wizard hides this, and in Terraform each piece is written out.
- The **NSG** is the Azure counterpart of an AWS security group, but it uses numbered priorities, can allow and deny, and is attached to a subnet or NIC. The portal's wizard opened SSH to the whole internet, so it had to be restricted to my own IP by hand afterwards.
- A **Standard SKU public IP is static**, so the address survived a stop and start. This differs from the AWS default, where the public IP changes.
- The portal offers the generated private key **once**. Losing that download means creating a new key pair.
- **Stopped vs. deallocated:** only a deallocated VM stops compute billing. Confirmed in the lab: after `az vm stop` the VM showed as stopped, with a warning that Azure continues to bill for the resources. Only after `az vm deallocate` did it show as deallocated.
- **Read the `Restrictions` column of `az vm list-skus` in detail.** A non-empty column does not mean the size is unusable. Mine said `NotAvailableForSubscription` for zones 2 and 3 only, so the size works, but only in zone 1 (or with no zone set, as in my Terraform). A plain "empty vs. not empty" check would have misled me.

## Terraform

- **`plan` passed and `apply` failed, twice.** `plan` does not know about regional or account restrictions:
  - `Microsoft.DevTestLab/schedules` is not available in Belgium Central (a resource type missing in a newer region).
  - My subscription is not allowed to create new resources in West Europe (an account-level restriction).
  - The same class of failure as the AWS Free Tier instance-type problem on Day 3. Check what is allowed before writing the code, for example with `az vm list-skus`.
- **Terraform does not roll back.** The eight resources that succeeded stayed, and the failed one was simply not created. A rerun only creates what is missing.
- Removing a resource block that was never created is harmless: the plan showed no changes. Removing one that exists means it gets destroyed.
- Terraform builds the order from references (resource group first, VM last), as on AWS.
- Terraform only needs the **public** key for the VM. The private key is never read.
- `*.tfvars`, `*.tfstate` and `inventory.ini` can contain subscription IDs or IPs, and `.pem` files contain secrets. All belong in `.gitignore`.

## Ansible

- The Terraform-to-Ansible link is again just a file: Terraform writes `inventory.ini`, Ansible reads it.
- **`--check` is not always reliable for service tasks.** On a fresh machine the dry run failed with `Could not find the requested service nginx`, because the package was not installed (dry runs do not install it). The real run worked. A failed `--check` is not necessarily a broken playbook.
- **Idempotency:** the second run changed nothing. The handler fired only when the page content changed, and not on the rerun.
- **Edit the playbook, never the live server.** My manual change to `index.html` was overwritten on the next run. The playbook describes the desired state, and Ansible restores it.
- A passphrase-protected key works with Ansible only through `ssh-agent`, because Ansible cannot type the passphrase. In WSL, load it with `ssh-add` once per session.
- The key must be copied into WSL's own filesystem (`~/.ssh/`), because `chmod` does not work on `/mnt/d/`. I also put `StrictHostKeyChecking=accept-new` in the inventory, because an `ansible.cfg` on `/mnt/d/` is ignored when the folder is world-writable.

## Mistakes and fixes worth remembering

| What happened | Lesson |
|---|---|
| `Permissions are too open` on the `.pem` file | Windows ACLs must contain only my user. Remove the inherited entries with `icacls` |
| Auto-shutdown resource failed in two regions | Not every resource type exists in every region. The portal's auto-shutdown also asked for a webhook, which is unresolved |
| Failed `apply` left 8 of 9 resources running | Always check `terraform state list` after a failure |

## Production notes (lab vs. production)

- **Network:** SSH and HTTP from my own IP is fine for a lab. Production uses a bastion, VPN or managed session access, and not direct public SSH.
- **Keys:** a passphrase on a laptop key is good practice. Production automation uses short-lived credentials or workload identity, and not long-lived keys.
- **Host key checking:** `accept-new` is a lab shortcut. Production pins known host keys.
- **Cost control:** manual destroy is acceptable for a lab. Production uses tagging, budgets, schedules and cleanup policies.
- **Web content:** copying a page with a playbook is a demo. Production deploys from a pipeline or a pre-built image.

## Mapping file (`aws-azure-mapping.md`): updates after Day 1

| Open item | Status |
|---|---|
| Azure dynamic vs. static public IP on stop/start | **Confirmed** for a Standard SKU static IP: the address stayed the same. Dynamic behavior not tested |
| Stopped vs. deallocated billing | **Confirmed**: stopped shows a billing warning, only deallocated stops compute billing |
| `plan` passes, `apply` fails on Azure | **Confirmed**, two examples (region and resource type, account restriction) |
| Terraform with `azurerm` for VM + NSG | **Done**; note that the schedule resource is unavailable in Belgium Central |

## Open questions

- Can auto-shutdown be enabled in Belgium Central at all (portal webhook requirement)?
- Is West Europe permanently closed to this subscription, or only for some resource types?
- Zones 2 and 3 are restricted for this subscription in Belgium Central. Does this limit later labs (availability zones, Azure Backup, Site Recovery)?
