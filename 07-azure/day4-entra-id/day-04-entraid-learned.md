# Day 4, part 1: What I learned (Entra ID as code, groups, Azure RBAC)

## Entra ID and Azure RBAC are two systems

- **Entra ID** answers *who you are* (users, groups). **Azure RBAC** answers *what you may do* on Azure resources (a role, at a scope). Terraform needs two providers for it: `azuread` for identities and `azurerm` for the role assignments.
- Check access in the portal showed the effective role, the scope and **which group** the permission came from. Roles were assigned to **groups**, never to users. Adding a person to a group is then the only change needed.
- The scope showed as "This resource" because the role was assigned directly on `rg-tf-lab-day04`, not inherited from the subscription.
- Proven by logging in as the users: **Reader** could read the resource group but was denied creating a network (`AuthorizationFailed` for `Microsoft.Network/virtualNetworks/write`). **Contributor** could create and delete it. The error names the exact action, so it shows which permission is missing.
- The test users logged in with the Azure CLI without any block or MFA prompt, although MFA is on for the tenant. Reason: the policies that would stop them are not enforced for them (next section).

## Conditional Access, seen from the sign-in log

- The sign-in log has a **Report-only** tab that shows what a policy *would* have done to a sign-in, without enforcing it.
- `CA001-RequireMFA-AllUsers` (report-only) showed **user action required**: the TF users have no MFA registered, so if CA001 is switched on, a plain password login from the CLI would break. Remember this for the Intune and automation days.
- `CA003-BlockLegacyAuth` showed **not applied**: the Azure CLI uses modern authentication, so a legacy-auth block does not touch it.
- I did not record what `CA002` (compliant device, pilot group only) showed. The TF users are not in the pilot group.

## Drift: what Terraform sees and what it ignores

- A member added **by hand** to a Terraform-managed group (`grp-tf-readers`) was **not** seen: `terraform plan` said **No changes**. `azuread_group_member` manages only the memberships it created itself. This is a gap: a person can slip into a group outside the code and Terraform will not notice.
- A role assignment **deleted by hand** was seen at once: `Plan: 1 to add`, and `apply` restored it. The code is the source of truth for what it owns.
- So "no changes" does not mean "nothing changed in the tenant". It means nothing changed in what Terraform tracks.

## Activity Log

- The Activity Log recorded both the delete (CLI) and the restore (Terraform) of the role assignment as `roleAssignments/delete` and `roleAssignments/write`, each with a *Started* and a *Succeeded* event, a timestamp and the caller (`adm.lab`).
- The caller field says **who**, but both actions ran as the same account, so it did **not** show which **tool** made the call. On AWS, CloudTrail made that visible (`aws-cli` versus Terraform). On Azure I have not found the equivalent. I have not checked whether the tool is hidden in other fields of the event. **Still open.**
- How long events take to show up: not recorded.

## Teardown and rebuild

- `terraform destroy` removed exactly the 11 resources. The counts of users and groups went back to the baseline (5 and 6), proving the existing hand-built objects were never touched.
- Deleted users are kept in the Entra **recycle bin** (soft delete, 30 days). Recreating users with the **same names** while the old ones were still in the bin worked without a conflict, twice (11 added, 11 destroyed). Good news for the Day 17 capstone rebuild.
- The 11 resources were: 2 `random_password`, 2 users, 2 groups, 2 memberships, 1 resource group, 2 role assignments.

## CLI and PowerShell gotchas

- A `--query` with a closing parenthesis, such as `"length(@)"`, breaks on Windows because `az` is a batch file. Count in PowerShell with `Measure-Object`, or filter there.
- Variables and a temporary `AZURE_CONFIG_DIR` keep the test logins away from the main login. Always finish with `az logout`, remove the variable and confirm the active account.
- Read passwords into variables from `terraform output` and never print them. Error messages can contain the full sign-in name and tenant domain: replace them before pasting.

## Mistakes and fixes

| What happened | Lesson |
|---|---|
| `length(@)` failed with `invalid jmespath_type` | Parentheses in `--query` are unreliable on Windows. Count in PowerShell |
| Pasted an error with the full sign-in name and tenant domain | Replace names and IDs with placeholders before pasting |

No other mistakes in this part.

## Production notes (lab vs. production)

- **Identity sources:** the test users had Terraform-generated initial passwords. As on Day 2, such generated values sit in the state (not checked today). Production creates users from an HR or identity system, or uses invitations and temporary access passes, not passwords from code.
- **Test logins with a password:** a CLI login with user and password is a lab shortcut. Production uses MFA-protected interactive logins, and automation uses workload identity federation, never a user password.
- **Least privilege and time:** production gives roles to groups, scoped as narrowly as possible, and uses just-in-time elevation (such as Entra PIM) for admin roles. The lab used the standard Reader and Contributor roles at one resource group.
- **Conditional Access:** CA001 in report-only is exactly how production tests a policy before enforcing it. Check the Report-only results for service accounts and automation before switching a policy on.
- **Drift in groups:** to stop manual additions, production uses a group-membership design (a single owner process) and an audit of membership changes, because Terraform does not see members it did not create.
- **Audit:** production sends the Activity Log and the Entra audit and sign-in logs to a central place (Log Analytics) and alerts on role assignment writes and deletes. The lab read the log by hand.
- **Rebuild test:** destroy and re-apply twice was a lab test of repeatability. Production protects important identities against deletion and does not rely on the recycle bin.

## Mapping file (`aws-azure-mapping.md`): updates after Day 4, part 1

| Open item | Status |
|---|---|
| Activity Log: how to tell which identity or tool deleted a resource | **Partly done.** The identity (caller) is shown, and both write and delete are logged with timestamps. The **tool** (CLI or Terraform) was not identified |
| Entra ID with the `azuread` provider | **Done:** users, groups, memberships, with RBAC through `azurerm_role_assignment` |
| Entra ID vs. IAM (section 4) | **Seen in practice:** identity (Entra) and permission (RBAC role at a scope) are separate objects, joined by a role assignment. In AWS IAM the policy attached to the identity is both |

New row for section 2.6 or 4 (identity): *group-based RBAC; manual group changes are invisible to `azuread_group_member`.*

## Open questions

- Which field of an Activity Log event, if any, shows the tool (CLI, portal, Terraform) that made the call?
- How long does an Activity Log event take to appear after the action? (not recorded)
- Does a custom role (part E, skipped) change anything for the operator? A replaced role assignment (`-/+`) is expected, not tested.
- What does `CA002` show for a sign-in of a user in the pilot group? (not tested, and the pilot users must not be used as test subjects)
- Does the Azure CLI still work for the TF users after CA001 is switched from report-only to on?
