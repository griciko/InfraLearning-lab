# Day 4, part 1: Entra ID as code (users, groups, Azure RBAC)

**Folder:** `D:\GITlabs\infra-learning-lab\07-azure\day4-entra-id`
**Region:** `belgiumcentral` (only for the test resource group)
**Time:** about 3 hours (first half of the day). Part 2 (Hyper-V factory) is a separate plan file.
**Goal:** create test users, groups and group memberships in Entra ID with the `azuread` provider, give the groups different Azure permissions on one resource group (RBAC), prove the permissions work, read the Activity Log to see who changed what, then destroy everything and check what Entra keeps behind.

How to resume in a new chat: upload `project-handoff.md` and this file, then say "Let's start Day 4, part 1".

---

## The idea first

Two systems, easy to mix up:

```
Entra ID  (who you are)                 Azure RBAC  (what you may do)
 ├─ users                                 role assignment =
 ├─ groups  ───── members                   WHO (user/group)  +  ROLE  +  SCOPE
 └─ Entra roles (manage the directory)      e.g. grp-tf-readers + Reader + rg-tf-lab-day04
```

- **Entra roles** (like User Administrator) control the *directory*. **Azure roles** (Reader, Contributor, Owner) control *Azure resources*. Different systems, different places to assign.
- Best practice: assign roles to **groups**, then put people in groups. The user list changes often, the role assignments stay stable.
- AWS comparison: IAM mixes identity and permissions (users, groups, policies). In Azure the identity lives in Entra ID, and a role assignment connects it to a **scope** (management group, subscription, resource group, or one resource). A role given on a resource group does not leak to the rest of the subscription.

What we build (11 new resources in one Terraform project, nothing existing is touched):

```
2 users ── membership ──> 2 groups
                           ├─ grp-tf-readers     ── Reader      ─┐
                           └─ grp-tf-operators   ── Contributor ─┴─> rg-tf-lab-day04
```

Nothing here needs the E5 trial. Entra objects are free, so cost is not a problem today.

---

## Your existing tenant: rules for today

Your tenant already holds a hand-built lab: users (`adm.lab` Global Admin, `lab.user01`, `lab.user02`, the emergency admin `bg-admin01`, and the owner), groups such as `grp-lab-ca-pilot` and `grp-lab-intune-pilot`, MFA, three Conditional Access policies (CA002 is ON for the pilot group) and Intune with `W11-LAB01` joined. Today's project must live **next to** that without touching it.

1. **Create only, never change.** The plan must say `11 to add, 0 to change, 0 to destroy`. If anything existing shows up as changed or destroyed, stop and paste the plan.
2. **Test objects are prefixed `tf`:** users `tf.reader` and `tf.operator`, groups `grp-tf-readers` and `grp-tf-operators`. Your names starting with `Lab` and `grp-lab-` belong to the hand-built lab, and the cleanup checks must not confuse the two.
3. **No pilot group today.** `grp-lab-intune-pilot` already exists for the Intune days.
4. **Never use existing accounts as test subjects.** `lab.user01` is in `grp-lab-ca-pilot`, so CA002 (compliant device) would block a CLI login. `adm.lab` only *runs* Terraform and is never a test subject or modified. `bg-admin01` stays out of every experiment, is never added to a group by this project and is never put into Terraform.
5. **Do not change Conditional Access or MFA from Terraform today.** The new test users fall under CA001 and CA003 (report-only, they log but do not block). Part D shows how to read that.
6. **Terraform runs as `adm.lab`**, the account used on Days 1-3 (Global Administrator). It also needs an Azure Owner or User Access Administrator role to create role assignments. The Day 2 role assignment worked, so it probably has it, and Part A3 confirms. A Global Administrator running Terraform is fine for a lab. In production a pipeline uses a dedicated identity with only the roles it needs.

---

## Part 0 (optional, only if needed): leftovers from Day 3 (10-15 min)

Do these in the morning if you haven't yet:

1. Open `07-azure\day3-snapshots-backup\workload\terraform.tfvars` and delete the `restore_snapshot_id` line (the snapshot it points to no longer exists).
2. Commit the Day 3 files (list at the end of `day-03-actions.md`). Never commit `terraform.tfvars`.
3. Quick sanity check: `az group list -o table` shows only `NetworkWatcherRG` and `rg-tfstate`.

---

## Part A: Checks and preparation (20 min)

```powershell
cd D:\GITlabs\infra-learning-lab\07-azure
mkdir day4-entra-id
cd day4-entra-id
Copy-Item ..\day3-snapshots-backup\backup\terraform.tfvars .
Copy-Item ..\day3-snapshots-backup\backup\backend.tf .
(Get-Content .\backend.tf) -replace 'day3-backup\.tfstate','day4-entra.tfstate' | Set-Content .\backend.tf
Select-String .\backend.tf -Pattern 'key'
```

The last line must show `day4-entra.tfstate`.

**A1. Which tenant and which domains?** (The names are fine to read, don't paste IDs.)

```powershell
az rest --method get --url "https://graph.microsoft.com/v1.0/domains" --query "value[].{name:id, initial:isInitial, default:isDefault}" -o table
```

You should see an `*.onmicrosoft.com` domain with `initial = True`. New test users get that domain. Check that it is the **same tenant as your M365 E5 trial** (you know the name). If it is a different one, tell me before going on.

**A2. Which account is logged in, and does it have the Entra role?**

```powershell
az account show --query user.name -o tsv
az rest --method get --url "https://graph.microsoft.com/v1.0/me/memberOf" --query "value[].displayName" -o tsv
```

The first line must be `adm.lab`'s sign-in name (do not paste it). The second lists its directory roles and groups: you should see **Global Administrator**. If you see another account, run `az login` as `adm.lab` first.

**A3. Does it have an Azure Owner role?** Creating role assignments needs Owner or User Access Administrator on the subscription:

```powershell
$me = az ad signed-in-user show --query id -o tsv
az role assignment list --assignee $me --all --query "[].roleDefinitionName" -o tsv
```

Expect `Owner`. (Do not paste the scope, it contains the subscription ID.) If it only shows `Contributor`, tell me before going on: Part B then needs one extra role for `adm.lab`.

**A3b. Baseline of your existing tenant** (for the check at the end):

```powershell
az ad user list --query "length(@)"
az ad group list --query "length(@)"
```

Write both numbers down.

**A4. Add two lines to `terraform.tfvars` without printing them:**

```powershell
$tid = az account show --query tenantId -o tsv
Add-Content .\terraform.tfvars "`ntenant_id = `"$tid`""
Add-Content .\terraform.tfvars "usage_location = `"XX`""
```

Then open the file and replace `XX` with **your two-letter country code** (uppercase). The usage location is needed later if a user gets a license (Intune days). Remove the `my_ip` line from the file if it is there, the project doesn't use it.

**A5. `.gitignore`** must still contain `*.tfvars`, `*.tfstate`, `*.tfstate.*`, `.terraform/`.

---

## Part B: Terraform project: users, groups, memberships, RBAC (45 min)

Create these files in `day4-entra-id\`. `backend.tf` is already there.

**`variables.tf`**
```hcl
variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "usage_location" {
  type        = string
  description = "Two-letter country code for the test users"
}

variable "location" {
  type    = string
  default = "belgiumcentral"
}
```

**`main.tf`**
```hcl
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# The tenant's *.onmicrosoft.com domain, used for the user names
data "azuread_domains" "initial" {
  only_initial = true
}

locals {
  domain = data.azuread_domains.initial.domains[0].domain_name

  tags = {
    project = "infra-learning-lab"
    day     = "04"
  }

  groups = {
    readers   = { name = "grp-tf-readers", description = "Terraform test: read-only on the Day 4 resource group" }
    operators = { name = "grp-tf-operators", description = "Terraform test: contributor on the Day 4 resource group" }
  }

  users = {
    reader   = { display = "TF Reader", nick = "tf.reader", group = "readers" }
    operator = { display = "TF Operator", nick = "tf.operator", group = "operators" }
  }
}

# Generated passwords. They end up in the state file (same lesson as Day 2).
resource "random_password" "user" {
  for_each    = local.users
  length      = 20
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "azuread_user" "lab" {
  for_each = local.users

  user_principal_name   = "${each.value.nick}@${local.domain}"
  display_name          = each.value.display
  mail_nickname         = each.value.nick
  password              = random_password.user[each.key].result
  force_password_change = false # lab shortcut, see production note
  usage_location        = var.usage_location
  account_enabled       = true
}

resource "azuread_group" "lab" {
  for_each = local.groups

  display_name     = each.value.name
  description      = each.value.description
  security_enabled = true
  mail_enabled     = false
}

resource "azuread_group_member" "lab" {
  for_each = local.users

  group_object_id  = azuread_group.lab[each.value.group].object_id
  member_object_id = azuread_user.lab[each.key].object_id
}

# A resource group only to hold the permissions test
resource "azurerm_resource_group" "rbac" {
  name     = "rg-tf-lab-day04"
  location = var.location
  tags     = local.tags
}

resource "azurerm_role_assignment" "readers" {
  scope                = azurerm_resource_group.rbac.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.lab["readers"].object_id
  principal_type       = "Group"
}

resource "azurerm_role_assignment" "operators" {
  scope                = azurerm_resource_group.rbac.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.lab["operators"].object_id
  principal_type       = "Group"
}
```

**`outputs.tf`**
```hcl
output "user_principal_names" {
  value = { for k, u in azuread_user.lab : k => u.user_principal_name }
}

output "initial_passwords" {
  value     = { for k, p in random_password.user : k => p.result }
  sensitive = true
}
```

**Things worth understanding**
- **`for_each`** builds two users, two groups and two memberships from two small maps. Add a user to the map and one `apply` creates user and membership.
- **`azuread_group_member`** adds *one* member to a group. We use it on purpose, and Part F shows what that means.
- **`principal_type = "Group"`** tells Azure what kind of principal it is, which avoids errors when a brand new group has not replicated yet.
- **`force_password_change = false`** is a lab shortcut so a CLI login works. Production forces a change at first sign-in.

**Run it**

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
```

- `init` must say `Successfully configured the backend "azurerm"`.
- If `validate` reports an argument problem in an `azuread_*` resource, paste me the exact error. I verified the provider's setup and domain data source in its documentation, but not every argument of the newest 3.x release.
- Expect **`Plan: 11 to add, 0 to change, 0 to destroy`**: 2 passwords, 2 users, 2 groups, 2 memberships, 1 resource group, 2 role assignments. No `~` or `-` lines. If an existing user, group or policy shows up as changed or destroyed, **stop** and paste the plan.

```powershell
terraform apply
```

Type `yes`. Users and groups can take a few seconds each, because the provider waits for Entra replication. If it fails halfway, run `terraform state list` first and paste me the exact error.

Check in the portal (Entra ID, Users and Groups) that the two `TF` users and the two `grp-tf-` groups exist and that each user is in its group, and that your existing users and groups look unchanged.

---

## Part C: Read the permissions (15 min)

```powershell
$gid = az ad group show --group grp-tf-readers --query id -o tsv
az role assignment list --assignee $gid --all --query "[].roleDefinitionName" -o tsv
$gid = az ad group show --group grp-tf-operators --query id -o tsv
az role assignment list --assignee $gid --all --query "[].roleDefinitionName" -o tsv
```

Expect `Reader` and `Contributor`. Role assignments can take a few minutes to take effect, so wait before the next part.

In the portal: open the resource group `rg-tf-lab-day04`, then **Access control (IAM) → Check access**, search each test user and read the result. The portal shows the **effective** permissions, including those inherited through the group. Notice which scope each role is assigned at.

---

## Part D: Prove it by logging in as the users (25 min, should do)

Use a **separate Azure CLI config folder**, so your own login stays untouched.

**1. In your normal window** (project folder), read the passwords and your subscription ID. Do not paste them into the chat:

```powershell
terraform output -json initial_passwords
az account show --query id -o tsv
```

**2. Open a new PowerShell window** and set the variables there:

```powershell
$sub = "<your subscription id>"
$env:AZURE_CONFIG_DIR = "$env:TEMP\azcfg-lab"
```

**3. Log in as the reader.** The password ends up in your shell history, which is acceptable only for a throwaway lab user:

```powershell
az login -u tf.reader@<your-initial-domain> -p "<password>" --allow-no-subscriptions
az group show -n rg-tf-lab-day04 --subscription $sub --query name -o tsv
az network vnet create -g rg-tf-lab-day04 -n vnet-test --address-prefix 10.9.0.0/16 --subscription $sub
```

- The `group show` should work (Reader can read).
- The `vnet create` should fail with **AuthorizationFailed**. Write down the text, without IDs.

Now the operator:

```powershell
az logout
az login -u tf.operator@<your-initial-domain> -p "<password>" --allow-no-subscriptions
az network vnet create -g rg-tf-lab-day04 -n vnet-test --address-prefix 10.9.0.0/16 --subscription $sub
az network vnet delete -g rg-tf-lab-day04 -n vnet-test --subscription $sub
```

The create should work (Contributor can write), and the delete cleans up. Finally:

```powershell
az logout
Remove-Item Env:AZURE_CONFIG_DIR
```

**If the login is blocked** (an error about MFA or Conditional Access), stop fighting it and rely on the portal's Check access from Part C. Your tenant has MFA configured, and a block is possible. CA001 and CA003 are report-only and CA002 targets only `grp-lab-ca-pilot` (the test users are not members), so by themselves they should not block. A per-user MFA requirement could. A block is a finding for the notes, not a mistake. Never change Conditional Access or MFA today, because it could lock you out of the tenant.

**Bonus if the login works:** in the portal open Entra ID, Monitoring, Sign-in logs, pick the test user's sign-in and look at the Conditional Access / Report-only tab. It shows what CA001 and CA003 *would* have done to that sign-in. Write down the result for the notes.

---

## Part E (optional): A custom role (20 min)

Contributor allows far more than a person who only starts and stops VMs needs. Add this to `main.tf`:

```hcl
resource "azurerm_role_definition" "vm_operator" {
  name        = "lab-vm-operator"
  scope       = azurerm_resource_group.rbac.id
  description = "Lab: read VMs, start, restart, stop and deallocate"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
      "Microsoft.Compute/virtualMachines/powerOff/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.rbac.id]
}
```

Then change **only** the `operators` role assignment: remove the `role_definition_name = "Contributor"` line and add `role_definition_id = azurerm_role_definition.vm_operator.role_definition_resource_id`. Run `terraform plan` and read it: the assignment shows `-/+` (replaced), because the role of an assignment cannot be edited in place. Apply, wait a few minutes, and check with Check access that the operator can no longer create networks. Custom roles have a delay, and creation of this one may take a minute.

---

## Part F: Drift and the Activity Log (20 min)

**F1. A change outside Terraform that Terraform does not see.** In the portal, add `TF Operator` to `grp-tf-readers` by hand. Run `terraform plan`. I expect **No changes**, because `azuread_group_member` only manages the members it created and ignores extra ones. Write down what you actually see. Lesson: to make a group's member list exclusive, you manage members on `azuread_group` itself (the `members` argument), and you cannot mix the two styles. Remove the extra member again in the portal afterwards.

**F2. A change Terraform does see.** Delete the reader role assignment from the CLI:

```powershell
$gid = az ad group show --group grp-tf-readers --query id -o tsv
az role assignment delete --assignee $gid --role "Reader" --resource-group rg-tf-lab-day04
terraform plan
```

Expect `Plan: 1 to add`. Run `terraform apply` to restore it.

**F3. Who deleted it?** (closes an open item from the mapping file). After a few minutes:

```powershell
az monitor activity-log list --resource-group rg-tf-lab-day04 --offset 2h --query "[?contains(operationName.value, 'roleAssignments')].{op:operationName.value, status:status.value, time:eventTimestamp}" -o table
```

You should see the write and delete operations on role assignments. The raw output also has a `caller` field (your user, or the identity that made the call). Look at it, do not paste it. Write down which operations were visible, and how long the events took to appear. On AWS this was the CloudTrail question: which tool made the call.

---

## Part G: Teardown and what Entra keeps (20 min)

```powershell
terraform plan -destroy
terraform destroy
az group list -o table
az ad user list --query "[?starts_with(displayName, 'TF ')].displayName" -o tsv
az ad group list --query "[?starts_with(displayName, 'grp-tf-')].displayName" -o tsv
az ad user list --query "length(@)"
az ad group list --query "length(@)"
```

- `plan -destroy` should list **11** resources (12 if you did Part E).
- After the destroy, `rg-tf-lab-day04` must be gone and the first two lists must be empty. The last two numbers must equal your baseline from A3b, which proves your existing objects were never touched.
- **Deleted users are not gone yet.** Entra keeps them in a recycle bin for 30 days. Check:

  ```powershell
  az rest --method get --url "https://graph.microsoft.com/v1.0/directory/deletedItems/microsoft.graph.user" --query "value[?starts_with(displayName, 'TF ')].displayName" -o tsv
  ```

**G2. Rebuild test (10 min, should do).** Run `terraform apply` once more. This tests whether recreating users with the same names works while the old ones are in the recycle bin. Both outcomes are useful: it works, or it fails with a conflict message (paste me the text). This matters for the capstone rebuild on Day 17. Then `terraform destroy` again.

---

## Part H: What to send me at the end

1. The A1 result (initial domain present: yes or no, same tenant as the E5 trial: yes or no), the role names from A2 and A3 (names only), and the two baseline numbers from A3b.
2. The `Plan: ... to add` line and whether `apply` completed.
3. The Part C results (`Reader`, `Contributor`) and what Check access showed.
4. Part D: the reader's `AuthorizationFailed` text (without IDs), whether the operator's create worked, and any MFA or login blocks.
5. Part E: the plan lines for the `-/+` and the result, if you did it.
6. Part F: what F1 printed, the `Plan` line of F2, and which Activity Log operations you saw.
7. Part G: the destroy count, whether the recycle bin lists the users, and the result of the rebuild test.
8. Any errors and how you fixed them. **Do not paste passwords, the tenant or subscription IDs, the `caller` value or email addresses.**

---

## Priority if time runs short

- **Must do:** Parts A, B, C, G.
- **Should do:** Part D (login test), Part F (drift and Activity Log), G2.
- **Nice to have:** Part E (custom role). It can move to a later quiet slot.

## Likely problems

| Symptom | Likely cause | What to do |
|---|---|---|
| `init` 403 on the backend | Role not propagated, or wrong `key` | Check the `key` in `backend.tf`, wait a few minutes |
| `Insufficient privileges` creating users or groups | Your account lacks an Entra role | Check A2, paste me the error |
| `apply` fails on a role assignment | You are not Owner or User Access Administrator, or the new group has not replicated | Check A3, wait a minute, rerun `apply` |
| `az login` as a test user is blocked | MFA registration, security defaults, Conditional Access | Skip Part D, use Check access, note it |
| Vnet create as the operator is denied right after apply | Role assignment delay | Wait 3-5 minutes and retry |
| Rebuild fails with a name conflict | Deleted users still in the recycle bin | Paste me the text, do not delete anything by hand yet |
| Leftover users or groups | Forgot the destroy | Run the Part G commands |
| The plan shows changes or destroys on existing users, groups or policies | The code touches something it should not | **Stop**, do not apply, paste the plan |
