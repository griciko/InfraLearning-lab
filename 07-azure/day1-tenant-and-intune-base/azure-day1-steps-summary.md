# Azure Day 1 — Tenant, Hyper-V and the Windows 11 Intune Device

Steps summary for Wednesday 14 October 2026. Start of the Azure phase: tenant licensing and enrollment settings, a Hyper-V host on the lab server, and a Windows 11 Pro VM joined to Entra ID as the Intune test device.

**Lab vs. production:** everything here is lab work: one person, broad admin rights, trial licenses, a Hyper-V VM on the only domain controller, and a self-service tenant. The last section lists where production differs.

---

## State before the day

Already in place from the previous steps:

- Azure free account with the $200 credit, Entra ID Free, budget with email alerts
- Lab identities: `bg-admin01` (Lab Emergency Admin 01), `adm.lab` (daily lab admin), `lab.user01`, `lab.user02`
- Security groups: `grp-lab-ca-exclude` (the emergency account), `grp-lab-ca-pilot` (`lab.user01`, for Conditional Access tests), `grp-lab-intune-pilot` (both lab users, for Intune tests)
- MFA enabled for all users
- A physical lab server (Windows Server 2025, AD DS and DNS, also the only domain controller) to host the Hyper-V VM

---

## Part A — Tenant

| Step | Action | Result |
|---|---|---|
| A1 | Started the Microsoft 365 E5 trial from the Microsoft 365 admin center, inside the existing tenant | Trial running |
| A2 | Reviewed roles, how MFA was enabled (security defaults or per-user), group membership, and registered authentication methods | Completed as planned |
| A3 | Set the usage location on the two lab users and assigned the E5 license **to the group** `grp-lab-intune-pilot` (group-based licensing) | License assigned to the pilot group |
| A4 | Set who may join devices, set the MDM user scope to `grp-lab-intune-pilot`, confirmed Intune as the MDM authority | Completed as planned |
| A5 | Tested the emergency account `bg-admin01` in a separate browser session | Completed as planned |

Notes:

- The license assignment needs a **usage location** on every user, which is why it comes first.
- Group-based licensing needs Entra ID P1 or P2, which the trial provides.
- Administrators don't need an Intune license for the portals, only roles, so only the pilot group was licensed.

---

## Part B — Hyper-V host and the Windows 11 VM

| Step | Action | Result |
|---|---|---|
| B1 | Checked the Hyper-V role on the lab server and prepared `D:\ISO` and `D:\VMs` (C: has only 79 GB) | Host ready |
| B2 | Created an external virtual switch `vSwitch-LAN`, sharing the adapter with the host | Server kept its address, DNS and the domain controller stayed healthy |
| B3 | Created the VM `W11-LAB01` with `new-w11-vm.ps1`: Generation 2, 4 GB fixed memory, 2 vCPUs, 80 GB dynamic disk, virtual TPM, Secure Boot, booting from the Windows 11 ISO | VM created and started |
| B4 | Installed Windows 11 Pro (custom install, no product key) | Installed without the CPU-check workaround; the server worked properly throughout |

Notes:

- The server's CPU (Intel 7th generation) isn't on Windows 11's supported processor list, so the installer's CPU check was the main risk. It did not block the installation.
- The VM files live on `D:` because `C:` is small.
- The switch creation briefly interrupts the network of the server, so remote sessions may disconnect.

---

## Part C — Entra join

| Step | Action | Result |
|---|---|---|
| C1 | Left the VM's DNS on DHCP (a cloud join, not a domain join) | Internet access from the VM |
| C2 | Joined the VM to Entra ID as `lab.user01`, passing MFA | Joined |
| C3 | Checked `dsregcmd /status` on the VM | `AzureAdJoined : YES`, MDM details present, no errors |

---

## Part D — Verification

| Step | Action | Result |
|---|---|---|
| D1 | Checked the device in Intune (Devices → Windows) and forced a sync | Completed as planned |
| D2 | Checked the server: VM state, memory, `dcdiag /q` | Server healthy |
| D3 | Took a Hyper-V checkpoint `after-enroll` | Taken. Not to be restored after Entra and Intune changes, because a reverted device can lose its trust relationship |

---

## Lessons from the day

- Use a **separate browser profile or InPrivate window per identity**, to avoid mixed sessions
- A license can't be assigned without a **usage location**
- License **groups**, not individual users, once the trial provides P1 or P2
- Keep VM files on the **larger drive**
- Creating an external switch on a server interrupts its network briefly: plan for a reconnect
- Don't restore a Hyper-V checkpoint after the device has enrolled: delete the VM and enroll again

---

## Lab vs. production

| Topic | In the lab | In production |
|---|---|---|
| Hyper-V host | The only domain controller also hosts the VM | Domain controllers carry no other roles, and hosts are separate |
| Administration | `adm.lab` as Global Administrator | Least privilege, just-in-time elevation, separate admin accounts |
| Licensing | Trial licenses on a pilot group | Purchased licenses, group-based assignment, license reporting |
| Test device | A VM enrolled by a user join | Autopilot or a managed enrollment process with corporate ownership |
| Emergency account | One tested account with a factor kept in the lab | Two or more accounts, hardware-bound credentials, monitored sign-ins |
| Windows 11 | A VM on an unsupported CPU generation | Supported hardware only |

---

## Files in this folder

- `new-w11-vm.ps1`: creates the Windows 11 lab VM on the Hyper-V host

**Keep out of the repo:** tenant names and IDs, passwords, and the server's IP address.

---

*Result: an E5 trial with the pilot group licensed, enrollment scoped to the pilot group, and a Windows 11 Pro VM running on the Hyper-V host, joined to Entra ID and ready for Intune policies and Conditional Access.*
