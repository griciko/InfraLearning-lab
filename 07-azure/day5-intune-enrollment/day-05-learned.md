# Day 5 learned (29 Oct 2026): Entra join, Intune enrollment, compliance, platform script

## 1. Concepts

| Word | What it is | Seen today |
|---|---|---|
| **Join** | The device gets an identity in Entra ID | `AzureAdJoined YES`, visible in Entra within 2 minutes |
| **Enrollment** | The device registers with Intune and receives policy | `EnrollmentState 1` on the device, but the portal still showed a placeholder until the first check-in |
| **Compliance** | Intune evaluates the device against a policy | Not compliant (BitLocker), then Compliant after the edit |
| **Conditional Access** | The gate that can require compliance | Never involved: the test user is outside the pilot group, and Report-only showed nothing |

- **Placeholder device.** When enrollment starts, Intune creates an entry named `user_Windows_<date>_<time>`. It becomes the real device name after the first successful check-in.
- **The VM's Info page and the portal show different things.** The Access work or school, Info page lists managed *areas* ("Security"), not compliance results. Read the verdict in the portal.
- **Intune does not rerun a successful script.** Three syncs without an edit changed nothing. Editing and re-uploading the script reran it in about 2.5 minutes.
- **Two timings for compliance.** First verdict after assignment: 17 min. Re-evaluation after editing the policy: about 2 min.
- **Inherited assignments.** Nothing in this tenant is assigned to All users or All devices, so the new device inherited nothing. Everything it received, we assigned.

## 2. Gotchas

1. **Two tenant scopes gate a new test user, and both can be set to "Some".** *MDM user scope* decides who enrolls automatically. *Users may join devices* decides who may join at all. Both needed `grp-tf-intune-test` added. Both are tenant settings, so each change was approved and recorded for the Day 7 revert.
2. **A disabled `dmwappushservice` broke the first check-in.** The service was `Disabled` (most likely from the base image). Symptoms: Settings said "The sync could not be initiated", the portal said "Notifying device - failed", the device's own sync tasks failed with `0x800706D9`, yet there were **no errors** in the event log and the device was enrolled (`EnrollmentState 1`). Setting it to Manual and starting it fixed it at once. The fix now lives in `w11.yml`.
3. **Event log silence is not health.** The enrollment log held only Information events while the sync was failing. The scheduled task results and the service list found the cause.
4. **`win_shell` always prints `CHANGED`.** The header says nothing about the result, only the output below it does.
5. **`$s` exists only in the workstation window where it was created.** Every `Invoke-Command -Session $s` is typed on the workstation. A new window needs a new session. Typing it on the host fails with "Cannot validate argument on parameter 'Session'".
6. **The device name in the portal and the VM clock differ by an hour** (portal in UTC, VM in W. Europe time).
7. **Take the checkpoint before the join.** It worked on the vTPM VM. Never roll back after a completed join.

## 3. Mistakes and wrong turns

| What happened | Lesson |
|---|---|
| The first troubleshooting theory (firewall or endpoint-mapper services) was wrong. All those services were running | An error code only says what failed, not why. Check the services around it, in this case the device-management ones, before building a story on one code |
| Commands labelled "runs on the host" were typed on the host, where `$s` does not exist | Say clearly: type everything on the workstation, `Invoke-Command` sends it to the host |
| The idempotency experiment skipped the no-change sync before the edit | The test was repeated later, three times, after the v2 run. Same result, so the finding stands |
| The first Compliant state and several portal values were not written down | Write times and states down as they happen |

## 4. Lab vs. production

| Topic | Lab today | Production |
|---|---|---|
| Who may enroll | A test group added to the tenant-wide MDM scope and join setting, by hand | Scope set once by policy, usually *All* or a defined group, plus enrollment restrictions. Changes go through change control |
| License | Assigned by hand | Group-based licensing |
| Device ownership | Automatic enrollment showed **Corporate** | Corporate identifiers, Autopilot or device enrollment manager decide the ownership |
| Intune objects | Built by hand in the portal | As code (Day 7) or exported JSON, reviewed in a pipeline |
| Test device | One VM from a base disk, checkpoint before the join | Autopilot or a golden image, devices not hand-built |
| Compliance | Measured only, the user is outside Conditional Access | Compliance feeds Conditional Access, so a noncompliant device is blocked |
| Base image | Contained a disabled `dmwappushservice` | Images are tested against enrollment before use |
| Verification | Ansible reads the file on the machine, not only the portal | Same idea: check what is on the endpoint |

## 5. Mapping tracker updates (Intune and Defender rows, to apply later)

| Intune / Microsoft | AWS | Mapping |
|---|---|---|
| Entra join | none (IAM has no device identity) | Azure/Microsoft-only |
| Intune enrollment | none | Azure/Microsoft-only |
| Compliance policy | AWS Config rules (loosely: evaluates resources, not endpoints) | Maps loosely, *verify* |
| Platform script | SSM Run Command / State Manager, EC2 user data | Maps loosely |
| Intune Management Extension | SSM Agent | Maps loosely |
| Tenant scopes (MDM user scope, join setting) | none | Azure/Microsoft-only |

## 6. Open questions

- Why `CA001` (named AllUsers, report-only) produced no Report-only result for `tf.intune01`. The entry opened may have been the join sign-in, which is not always evaluated.
- Whether the base image should be rebuilt without the disabled `dmwappushservice`, or whether the playbook task is enough.
- Whether the Defender for Endpoint connection (Available, all settings off) can be switched on for a test device without touching the existing lab, and what compliance risk-level settings need it.
- Whether a provider resource can assign the license, or whether it stays manual (Day 7).
- Whether the existing-pilot policies (Edge profile, Security Baseline, EDR) could be tested on the new device without editing them (Day 6).
