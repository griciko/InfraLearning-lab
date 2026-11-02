# Day 1: Actions (first Azure VM, Terraform, Ansible)

**Date:** 25 October 2026
**Working folder:** `D:\GITlabs\infra-learning-lab\07-azure\01-linux-vm`
**Region:** `belgiumcentral` (Belgium Central)
**VM:** Ubuntu Server 24.04 LTS x64 Gen2, size `Standard_B2ats_v2` (2 vCPU, 1 GiB)

Already done before today: Azure budget alerts, `az login`, subscription and tenant IDs noted.

---

## 1. Manual VM in the portal

| Setting | Value |
|---|---|
| Availability | No infrastructure redundancy required |
| Security type | Standard |
| Authentication | SSH public key, generated in the portal (Ed25519) |
| Username | `azureuser` |
| Inbound ports | SSH (22) |
| Resource group | New, dedicated to the lab |

- The portal offered the private key (`.pem`) for download **once**. Saved as `D:\GITlabs\AZ\vm-linux-01_key.pem`.
- First `ssh` attempt failed with `Permissions ... are too open`.

Fix (PowerShell):

```powershell
$key = "D:\GITlabs\AZ\vm-linux-01_key.pem"
icacls $key /inheritance:r
icacls $key /remove "Users" "Authenticated Users" "Everyone" "BUILTIN\Users"
icacls $key /grant:r "${env:USERNAME}:R"
ssh -i $key azureuser@<VM-IP>
```

**Result:** connected to the VM over SSH.

## 2. Experiments on the manual VM

Commands used:

```powershell
az vm list -d -o table
az vm get-instance-view -g <RG> -n <VM> --query "instanceView.statuses[].displayStatus" -o tsv
az vm stop -g <RG> -n <VM>
az vm deallocate -g <RG> -n <VM>
az vm start -g <RG> -n <VM>
az network public-ip list -g <RG> --query "[].{name:name,sku:sku.name,alloc:publicIPAllocationMethod}" -o table
```

- The SSH rule in the NSG was restricted from the whole internet to my own public IP.
- **Public IP after stop and start:** unchanged. Reason: the portal created the IP with static allocation.
- **Stopped vs. deallocated statuses:**
  1. Running: normal state.
  2. After `az vm stop`: stopped, with a warning that Azure continues to bill for the resources.
  3. After `az vm deallocate`: deallocated, the state in which compute billing stops.
- The manual resource group was deleted afterwards with `az group delete`, so every resource in it was removed together.

## 3. Same VM with Terraform

Files in `01-linux-vm\`: `variables.tf`, `terraform.tfvars` (not committed), `main.tf`, `outputs.tf`.

Resources (8 on Azure): resource group, virtual network, subnet, network security group (SSH from my IP), NSG-subnet association, static public IP (Standard SKU), network interface, Linux VM.

A new SSH key pair was created for Terraform and Ansible, **with a passphrase**:

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\azure_lab
```

Standard sequence:

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### Errors on the first `apply`

My first version also contained an auto-shutdown schedule (`azurerm_dev_test_global_vm_shutdown_schedule`, the 9th resource). `plan` passed, `apply` failed.

| # | Error | Cause | What I did |
|---|---|---|---|
| 1 | `LocationNotAvailableForResourceType` for `Microsoft.DevTestLab/schedules` in `belgiumcentral` | The resource type is not offered in Belgium Central | Tried placing only the schedule in `westeurope` |
| 2 | `RequestDisallowedByAzure`: the selected region is currently not accepting new customers | My subscription may not create new resources in `westeurope` | Removed the schedule block from `main.tf` |

- Terraform does not roll back: the other 8 resources had already been created and stayed.
- The VM, the NSG rule and `apt update` / `apt upgrade` inside the VM were tested and worked.
- In the portal, auto-shutdown asked for a webhook to be enabled. **Not resolved.** Cost control stays manual: destroy, or deallocate, at the end of each session.

## 4. Terraform + Ansible: web server

Terraform changes:

- Added the `hashicorp/local` provider.
- Added a second NSG rule: HTTP (port 80) from my IP only (priority 110).
- Added a `local_file` resource that writes `inventory.ini` with the VM's IP.
- Added `inventory.ini` to `.gitignore`.

Because the first VM had been destroyed, the plan was a full build:

```
Plan: 9 to add, 0 to change, 0 to destroy.
```

(8 Azure resources + the inventory file.)

WSL preparation:

```bash
cp /mnt/c/Users/<USER>/.ssh/azure_lab ~/.ssh/azure_lab
chmod 600 ~/.ssh/azure_lab
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/azure_lab        # passphrase entered once
```

Playbook `webserver.yml`: installs nginx, deploys an `index.html`, makes sure the service runs and starts at boot, and has a handler that reloads nginx.

Run sequence (from WSL, with `path=/mnt/d/GITlabs/infra-learning-lab/07-azure/01-linux-vm`):

```bash
ansible -i $path/inventory.ini web -m ping
ansible-playbook -i $path/inventory.ini $path/webserver.yml --check
ansible-playbook -i $path/inventory.ini $path/webserver.yml
ansible-playbook -i $path/inventory.ini $path/webserver.yml
```

### Results

| Run | Result |
|---|---|
| `--check` (dry run) | Install and page tasks showed `changed`. The service task **failed**: `Could not find the requested service nginx: host`. `ok=3 changed=2 failed=1` |
| Real run | Install `changed`, page `changed`, service `ok`, handler `changed`. `ok=5 changed=3 failed=0` |
| Second real run | Idempotent: nothing changed |
| Manual edit of `index.html` on the VM, then playbook rerun | The manual change was overwritten by the playbook |

Other results:

- `ansible ... -m ping` returned `pong`.
- Outside test with `Invoke-WebRequest http://<VM-IP>` returned status 200, and the page was also visible in the browser at three moments: after the install, after the manual text change, and after the playbook restored the original text.

### VM size check (run before the build)

```powershell
az vm list-skus --location belgiumcentral --size Standard_B2ats --output table
```

```
ResourceType     Locations       Name               Zones    Restrictions
virtualMachines  BelgiumCentral  Standard_B2ats_v2  1,2,3    NotAvailableForSubscription, type: Zone, locations: BelgiumCentral, zones: 2,3
```

The size exists, but zones 2 and 3 are restricted for this subscription, so only zone 1 is usable. The Terraform VM does not set a zone, so it was created without a zone constraint and the restriction did not block it.

## 5. Cleanup (still to do)

- [ ] `terraform plan -destroy` (read it: 8 Azure resources + the inventory file)
- [ ] `terraform destroy`
- [ ] `az group list -o table`: lab resource group is gone
- [ ] `az resource list -o table`: nothing left
- [ ] `az vm list -d -o table`: no VM running

There is no auto-shutdown, so a VM left running keeps billing.

## 6. Files to commit

- `main.tf`, `variables.tf`, `outputs.tf`, `webserver.yml`, and these two day files.
- **Never commit:** `terraform.tfvars`, `*.tfstate`, `.terraform/`, `inventory.ini`, `*.pem`, private keys.
