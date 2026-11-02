# Day 5 actions (29 Oct 2026): Entra join, Intune enrollment, compliance policy, platform script

Plan file: `day5-IntuneEnrollment.md`. Folder: `07-azure\day5-intune-enrollment\` (with `identity\`).
Times are the VM clock (W. Europe Standard Time, UTC+1) unless stated. No secrets, IDs or tenant names in this file.

---

## 1. Pre-flight (parts A and B, read only)

| Item | Result |
|---|---|
| E5 trial | Expires 13 Nov 2026 (15 days left on 29 Oct, by date) |
| Free E5 licenses | 22 of 25 |
| MDM user scope | **Some**, group `grp-lab-intune-pilot` (members `lab.user01`, `lab.user02`) |
| Intune baseline | 1 device (`W11-LAB01`), 1 compliance policy (`W11-Compliance-Baseline`), 3 configuration profiles (Intune2Defender EDR, W11-Config-Edge-Lab, W11-Security-Baseline 26H2), 0 platform scripts, 1 app (Mozilla Firefox) |
| Tenant-wide setting "Mark devices with no compliance policy assigned as" | **Compliant** (validity period 30 days) |
| Entra baseline | 5 users, 6 groups |
| Defender for Endpoint connection (Intune) | Status **Available**, all settings **off** |
| Existing assignments to All users / All devices | **None.** Every existing policy, profile and app targets `grp-lab-intune-pilot` only |

## 2. Tenant settings changed (approved by the learner, to be reverted on Day 7)

| Setting | Before | Change | Why |
|---|---|---|---|
| Entra, Mobility (MDM and MAM), Microsoft Intune, **MDM user scope** | Some: `grp-lab-intune-pilot` | **Added** `grp-tf-intune-test` (pilot group kept) | Automatic enrollment only works for users in scope |
| Entra, Devices, Device settings, **Users may join devices** | Selected: one existing group | **Added** `grp-tf-intune-test` | The first join was refused for the test user |

Revert both on Day 7 (back to the original group only). Not changed: MAM scope, MFA, Conditional Access, tenant-wide compliance setting.

## 3. Terraform identity project (part C)

- Project `identity\`, state key `day5-intune-identity.tfstate`, providers `azuread ~> 3.0` and `random ~> 3.0`.
- `Plan: 4 to add, 0 to change, 0 to destroy` (password, user `tf.intune01`, group `grp-tf-intune-test`, membership). Apply: 4 added.
- Counts after apply: **6 users, 7 groups**.
- License (Microsoft 365 E5) assigned to `tf.intune01` **by hand** in the Microsoft 365 admin center.

## 4. The VM (part D)

- All commands typed on the workstation. `Invoke-Command -Session $s` sends the script block to the Hyper-V host.
- `New-LabVm.ps1` built `tf-w11-intune01` from `win11-base.vhdx` (differencing disk). `TpmEnabled True`, IP `192.168.88.82`.
- Ansible `w11.yml`: `pong`, rename to `TFINTUNE01` (`changed=4`), then `SecureBoot true`, `TpmPresent true`, `TpmReady true`. Second run `changed=0`.
- Checkpoint `pre-join` worked on the vTPM VM.

## 5. Entra join and enrollment (part E)

1. First join attempt refused: **"Administrator policy does not allow user ... to device join"**. Nothing was created. Fix: added `grp-tf-intune-test` to *Users may join devices* (section 2).
2. Retry: join finished at **17:11**. No MFA prompt (MFA to register or join is *No*). A Windows Hello PIN was set. The device was visible in Entra within 2 minutes.
3. `dsregcmd`: `AzureAdJoined YES`, `DomainJoined NO`, `TpmProtected YES`, `DeviceAuthStatus SUCCESS`, MDM URL present.
4. Entra shows: join type **Microsoft Entra joined**, MDM **Microsoft Intune**, registered 17:11:43.
5. **Problem:** Intune showed a placeholder device (`tf.intune01_Windows_<date>_<time>`) with no details. Settings, Sync said "The sync could not be initiated", and the portal Sync failed at "Notifying device".

### Troubleshooting (all read only until the fix)

| Check (Ansible `win_shell`) | Result |
|---|---|
| MDM URL in `dsregcmd` | Present |
| Device management event log, errors and warnings | None |
| `HKLM:\SOFTWARE\Microsoft\Enrollments` | `MS DM Server`, `EnrollmentState 1` (enrolled) |
| Enrollment scheduled tasks | Results `0x800706D9` (endpoint mapper), `0x8007045B`, `267011` (not run yet) |
| `mpssvc`, `RpcEptMapper`, `RpcSs`, `DcomLaunch`, `BFE` | All running. Firewall profiles all enabled |
| Port 443 to `manage.microsoft.com`, `enrollment.manage.microsoft.com`, `login.microsoftonline.com` | Reachable. No proxy. Clock and time zone fine |
| **`dmwappushservice`** | **Stopped, StartType Disabled** (`DmEnrollmentSvc` Stopped/Manual is normal) |

**Fix:** set `dmwappushservice` to Manual, start it, start the two enrollment sync tasks. Both returned `0` at about 18:07. The device then showed `TFINTUNE01`, ownership **Corporate**, an OS version and primary user `tf.intune01`.

```powershell
Set-Service dmwappushservice -StartupType Manual
Start-Service dmwappushservice
```

`w11.yml` now has a task (`ansible.windows.win_service`, `start_mode: manual`, `state: started`) so new VMs from the base image do not hit this.

Time from join to the first successful check-in: about 56 minutes, nearly all of it troubleshooting.

## 6. Compliance policy (part F)

- Policy `tf-comp-win-day5`, Windows 10 and later: BitLocker, Secure Boot, TPM and Firewall all **Require**. Default noncompliance action. Assigned to `grp-tf-intune-test` only.
- The VM's Settings, Access work or school, Info page listed only a "Security" area. That page lists managed areas, not compliance verdicts. The Intune portal is the place to read the verdict.
- Assigned **18:27**, verdict visible **18:44** (**17 min**). Result reported as expected (BitLocker not compliant, overall Not compliant). Per-setting values were not pasted.
- Fix: BitLocker set to **Not configured**, saved **18:47**, **Compliant at 18:49** (**about 2 min**).
- Conditional Access: the Report-only tab of the user's sign-in log showed **nothing** for `CA001`, `CA002` and `CA003`. Compliance was measured only, never enforced.

## 7. Platform script (part G)

- `tf-ps-day5-marker.ps1` writes `C:\ProgramData\lab\day5-intune.txt`. Settings: logged-on credentials No (SYSTEM), signature check No, 64-bit Yes. Assigned to `grp-tf-intune-test`.
- Assigned **18:57**. File written **19:02:01** (about **5 min**). The `IntuneManagementExtension` service was seen at 19:05. No errors.
- Verified from Ansible: `Deployed by Intune on 2026-10-29T19:02:01`.
- **Edit test:** added "v2", re-uploaded, saved **19:11**. File changed to `Deployed by Intune v2 on 2026-10-29T19:13:35` (about **2.5 min**, service restarted by hand).
- **No-change test:** three syncs with no edit left the file at 19:13:35. Intune does not rerun a successful, unchanged script.

## 8. Cleanup state at the end of the day

| Item | State |
|---|---|
| VM `tf-w11-intune01` | **Off**, kept for Days 6 and 7. `W11-LAB01` Off, untouched |
| `tf.intune01`, `grp-tf-intune-test`, E5 license | Kept until Day 7 |
| `tf-comp-win-day5`, `tf-ps-day5-marker` | Kept until Day 7 |
| MDM scope and device join setting | **Changed, to be reverted on Day 7** |
| `C:\Temp\lab` on the host | Removed |
| Session, `$pw`, `WIN_PASS` | Closed, removed, unset |

## 9. Day 7 teardown additions

Delete the device in Intune and in Entra (before or with the VM), the compliance policy, the platform script, the license assignment, then `terraform destroy` in `identity\`. Revert the MDM user scope and the device join setting to the original group only. Expect 5 users and 6 groups afterwards.

## 10. Files to commit

Committed: `identity\*.tf`, `tf-ps-day5-marker.ps1`, `w11.yml` (with the `dmwappushservice` task).
Never: `inventory.ini`, `terraform.tfvars`, `*.tfstate`, `.terraform\`.

## 11. Not recorded

- The first Compliant state before the policy was assigned (expected Compliant from the tenant setting).
- Entra's *Compliant* column for the device.
- The per-setting compliance values after the first verdict.
- The time the device first appeared in Intune (as the placeholder).
- Why no Conditional Access result appeared for `CA001`.
