# Day 4, part 2: Hyper-V VM factory (Windows 11, Gen2, vTPM), PowerShell, Terraform, Ansible

**Folder:** `D:\GITlabs\infra-learning-lab\07-azure\day4-hyperv-factory`
**Hyper-V host:** `192.168.88.200` (Windows Server 2025). VM files live under `D:\HypVMs` on the host. The ISOs are in `D:\ISOtools` (`Win11t.iso`, `Windows10.iso`).
**Time:** about 4 hours in two stretches: **stretch 1 = Parts A to D** (about 2 h), **stretch 2 = Parts E to G** (about 2 h).
**Goal:** build a reusable Windows 11 base disk from the ISO, create Gen2 VMs with Secure Boot and a virtual TPM from it in seconds, reach them with Ansible over WinRM, try the same VM with Terraform, then tear the test VMs down and keep the base disk for the Intune days.

How to resume in a new chat: upload `project-handoff.md` and this file, then say "Let's start Day 4, part 2".

---

## The idea first

Clicking through a Windows installer for every VM is slow and cannot be repeated. A factory builds the expensive part once and copies the cheap part many times:

```
Workstation (PowerShell, Terraform, WSL for Ansible)
   │  WinRM 5985 (PowerShell remoting)
   ▼
Hyper-V host 192.168.88.200
  D:\ISOtools\Win11t.iso                  (input, never changed)
  D:\HypVMs\
    W11-LAB01                             (hand-built, Entra-joined: NEVER touch)
    tf-images\win11-base.vhdx             (built once, never booted, read-only parent)
    tf-vms\tf-w11-01\tf-w11-01.vhdx       (differencing child: only the differences, small)
    tf-vms\tf-w11-02\...
```

How the base disk is built (no installer, no clicking):

1. Create an empty GPT disk (`New-VHD`), partition it (boot partition and Windows partition).
2. **Apply** the Windows image from the ISO onto it (`Expand-WindowsImage`), then make it bootable (`bcdboot`).
3. Drop an **answer file** (`unattend.xml`) into `Windows\Panther`. At the first boot Windows reads it, skips the setup screens, creates a local admin `labadmin`, and turns on WinRM.
4. The disk is **never booted**, so it needs no sysprep. It is set to read-only and becomes the parent of all VMs.

Each VM is a **differencing disk** that points at the parent, plus a Gen2 VM with Secure Boot and a vTPM. AWS comparison: the base disk is like an AMI and the differencing disk is like a volume created from it, but the child stays tied to its parent file.

Why not click through the Windows 11 installer? Microsoft keeps removing the "local account" tricks from Windows 11 setup (`oobe\bypassnro` and `start ms-cxh:localonly` were reported as removed in recent builds), so an unattended image is more reliable than a manual install. The vTPM and Secure Boot matter later: Intune compliance and Autopilot expect a TPM.

Order of the lab, in one sentence each: **PowerShell** builds the base and the VMs (the cmdlets I checked), **Ansible** configures the guest over WinRM, and **Terraform** with the community `taliesins/hyperv` provider repeats the VM step declaratively, if the provider can do what we need (a gate in Part F decides).

Cost: nothing in Azure today. The only costs are RAM and disk on the Hyper-V host.

---

## Rules for today (the host has a hand-built lab on it)

1. **Read first, create only `tf` objects.** Everything new is prefixed `tf`: VM names `tf-w11-01`, folders `tf-images` and `tf-vms`. The scripts refuse other names.
2. **Never touch `W11-LAB01`.** Do not start, stop, edit or clone it. It is Entra-joined, and a clone of a joined machine would carry its identity.
3. **Never create or change a virtual switch from a remote session.** An external switch rebinds the host's network card, and the connection you are using to manage it drops. Reuse the switch `W11-LAB01` already uses.
4. **No Entra join, no Intune enrollment today.** The base disk must stay unjoined and unbooted. Joining comes on the Intune days.
5. **Never put the host password or the VM password into the chat, into Git or into files in the repo.**
6. Windows 10 is out of mainstream support since October 2025, so today builds Windows 11 only. The scripts take the ISO as a parameter, so `Windows10.iso` can be tried at the end if time is left.

---

## Part A: Prepare the workstation and connect to the host (20 min)

```powershell
cd D:\GITlabs\infra-learning-lab\07-azure
mkdir day4-hyperv-factory
cd day4-hyperv-factory
```

**A1. Can you reach the host?**

```powershell
Test-NetConnection 192.168.88.200 -Port 5985
Test-WSMan 192.168.88.200
```

- `TcpTestSucceeded : True` and a `Test-WSMan` answer mean PowerShell remoting is on. Go to A2.
- If port 5985 is closed, enable remoting **on the host** (RDP or console, PowerShell as administrator): `Enable-PSRemoting -Force`, then repeat.
- If `Test-WSMan` fails with a trust error, the host is not in a domain. On the workstation (PowerShell as administrator) add it to the trusted hosts: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value 192.168.88.200 -Concatenate -Force`. This is a lab shortcut. Production uses HTTPS or Kerberos.

**A2. Open one session and keep it for the whole day.** Use a local administrator of the host:

```powershell
$cred = Get-Credential
$s = New-PSSession -ComputerName 192.168.88.200 -Credential $cred -Authentication Negotiate
Invoke-Command -Session $s -ScriptBlock { hostname; (Get-Module -ListAvailable Hyper-V).Name }
```

Expect the host name and `Hyper-V`. Variables are lost when the window closes, so if you close it, repeat A2.

**A3. Create the folders on the host** (only `tf` folders, nothing existing is touched):

```powershell
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Force -Path C:\Temp\lab, D:\HypVMs\tf-images, D:\HypVMs\tf-vms | Select-Object FullName }
```

---

## Part B: Read-only recon (15 min)

Nothing here changes anything. Run each block and keep the output for the notes and for me.

**B1. VMs, switches, disk and memory on the host**

```powershell
Invoke-Command -Session $s -ScriptBlock { Get-VM | Select-Object Name, State, Generation, Path | Format-Table -AutoSize }
Invoke-Command -Session $s -ScriptBlock { Get-VMSwitch | Select-Object Name, SwitchType | Format-Table -AutoSize }
Invoke-Command -Session $s -ScriptBlock { Get-VMNetworkAdapter -VMName W11-LAB01 | Select-Object VMName, SwitchName | Format-Table -AutoSize }
Invoke-Command -Session $s -ScriptBlock { Get-PSDrive D | Select-Object @{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}, @{n='UsedGB';e={[math]::Round($_.Used/1GB,1)}} }
Invoke-Command -Session $s -ScriptBlock { $os = Get-CimInstance Win32_OperatingSystem; [pscustomobject]@{ TotalGB = [math]::Round($os.TotalVisibleMemorySize/1MB,1); FreeGB = [math]::Round($os.FreePhysicalMemory/1MB,1) } }
```

- Note the **switch name** `W11-LAB01` uses. Today's VMs use the same one (rule 3).
- Note **free space on D:** (the base disk needs up to about 25 GB, each child a few GB) and **free memory** (each VM gets 4 GB).

**B2. Is the ISO on the host, and which Windows editions does it hold?**

```powershell
Invoke-Command -Session $s -ScriptBlock { Test-Path D:\ISOtools\Win11t.iso }
```

If this prints `False`, the ISO is on your workstation's `D:` and not on the host's `D:`. Tell me and we copy it with `Copy-Item -ToSession`. If `True`:

```powershell
Invoke-Command -Session $s -ScriptBlock {
  $iso = 'D:\ISOtools\Win11t.iso'
  $img = Mount-DiskImage -ImagePath $iso -PassThru
  $dl  = ($img | Get-Volume).DriveLetter
  $wim = "${dl}:\sources\install.wim"
  if (-not (Test-Path $wim)) { $wim = "${dl}:\sources\install.esd" }
  $wim
  Get-WindowsImage -ImagePath $wim | Select-Object ImageIndex, ImageName, @{n='SizeGB';e={[math]::Round($_.ImageSize/1GB,1)}} | Format-Table -AutoSize
  Dismount-DiskImage -ImagePath $iso | Out-Null
}
```

Pick the **ImageIndex** of a **Pro** or **Enterprise** (or Education) edition. Windows 11 Home cannot be joined to Entra ID for the Intune days. Write the index down.

---

## Part C: Build the base disk (30-40 min, mostly waiting)

**C1. Create `New-LabBaseImage.ps1`** in `day4-hyperv-factory\` on the workstation:

```powershell
param(
  [Parameter(Mandatory)][string]$IsoPath,
  [Parameter(Mandatory)][int]$Index,
  [Parameter(Mandatory)][string]$OutVhdx,
  [Parameter(Mandatory)][string]$AdminPassword,
  [string]$TimeZone = 'W. Europe Standard Time',
  [int]$SizeGB = 64
)

$ErrorActionPreference = 'Stop'

# Safety rules: never overwrite, only write into a tf-images folder
if (Test-Path $OutVhdx) { throw "Already exists: $OutVhdx" }
if ($OutVhdx -notlike '*\tf-images\*') { throw "Output must be inside a 'tf-images' folder" }

$vhdMounted = $false
try {
  # 1. Mount the ISO and find the image file
  $iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
  $isoDrive = ($iso | Get-Volume).DriveLetter
  $wim = "${isoDrive}:\sources\install.wim"
  if (-not (Test-Path $wim)) { $wim = "${isoDrive}:\sources\install.esd" }
  Write-Host "Image file: $wim"

  # 2. Empty GPT disk with a boot partition and a Windows partition
  New-VHD -Path $OutVhdx -SizeBytes ($SizeGB * 1GB) -Dynamic | Out-Null
  $disk = Mount-VHD -Path $OutVhdx -Passthru | Get-Disk
  $vhdMounted = $true
  Initialize-Disk -Number $disk.Number -PartitionStyle GPT

  $esp = New-Partition -DiskNumber $disk.Number -Size 260MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
  $null = $esp | Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false
  $esp | Add-PartitionAccessPath -AssignDriveLetter
  $esp = Get-Partition -DiskNumber $disk.Number -PartitionNumber $esp.PartitionNumber
  $espDrive = $esp.DriveLetter

  $win = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
  $null = $win | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false
  $win = Get-Partition -DiskNumber $disk.Number -PartitionNumber $win.PartitionNumber
  $winDrive = $win.DriveLetter
  Write-Host "Boot partition ${espDrive}: Windows partition ${winDrive}:"

  # 3. Apply the Windows image and make the disk bootable (UEFI)
  Write-Host "Applying image index $Index, this takes several minutes..."
  Expand-WindowsImage -ImagePath $wim -Index $Index -ApplyPath "${winDrive}:\" | Out-Null
  & bcdboot "${winDrive}:\Windows" /s "${espDrive}:" /f UEFI
  if ($LASTEXITCODE -ne 0) { throw "bcdboot failed with exit code $LASTEXITCODE" }

  # 4. Answer file: skips setup screens, creates the local admin, turns on WinRM at first logon
  $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <ComputerName>*</ComputerName>
      <TimeZone>$TimeZone</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <ProtectYourPC>3</ProtectYourPC>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>labadmin</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>$AdminPassword</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>labadmin</Username>
        <Password>
          <Value>$AdminPassword</Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Enable WinRM for the lab</Description>
          <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private; Enable-PSRemoting -Force -SkipNetworkProfileCheck; New-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force; Enable-NetFirewallRule -DisplayName 'File and Printer Sharing (Echo Request - ICMPv4-In)'"</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"@
  $panther = "${winDrive}:\Windows\Panther"
  New-Item -ItemType Directory -Path $panther -Force | Out-Null
  Set-Content -Path "$panther\unattend.xml" -Value $xml -Encoding UTF8
  Write-Host 'Answer file written.'
}
finally {
  if ($vhdMounted) { Dismount-VHD -Path $OutVhdx }
  Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}

# Parent disks must not change once children exist
Set-ItemProperty -Path $OutVhdx -Name IsReadOnly -Value $true
Get-VHD -Path $OutVhdx | Select-Object Path, VhdType, Size, FileSize
```

**What the answer file does** (read it once, it is the heart of the factory):
- `ComputerName *` lets Windows pick a random name. Ansible renames the machine later.
- `HideOnlineAccountScreens`, `SkipMachineOOBE` and the others skip the setup screens, and `LocalAccounts` creates `labadmin`, so no Microsoft account is needed.
- `AutoLogon` logs `labadmin` in once, which triggers `FirstLogonCommands`. These set the network profile to Private, turn on WinRM, and allow remote administration with a local account (`LocalAccountTokenFilterPolicy`), and allow ping.
- **The password is stored in plain text in this file** (`PlainText true`), the same lesson as the Terraform state on Day 2. Part E checks whether it is still there after the first boot.

**C2. Create the admin password and store it safely.** The password is baked into the base disk, so if you lose it you must rebuild the disk. The commands keep it out of the screen, out of the chat and out of the repo, and store it encrypted for your Windows user in a file outside the repo:

```powershell
$pw = 'Aa1' + (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 17 | ForEach-Object { [char]$_ }))
"[$($pw.Length)]"
$sec = ConvertTo-SecureString $pw -AsPlainText -Force
New-Object System.Management.Automation.PSCredential('labadmin', $sec) | Export-Clixml "$env:USERPROFILE\lab-labadmin.cred.xml"
Test-Path "$env:USERPROFILE\lab-labadmin.cred.xml"
```

Expect `[20]` and `True`. The file is encrypted with Windows DPAPI: only your user on this machine can read it back. To get the password back later (also after closing the window):

```powershell
$pw = (Import-Clixml "$env:USERPROFILE\lab-labadmin.cred.xml").GetNetworkCredential().Password
```

**C3. Copy the script to the host and run it.** Put your **ImageIndex** from B2 in `$idx`:

```powershell
$idx = 0   # replace 0 with your index
"[$idx]"
Copy-Item .\New-LabBaseImage.ps1 -Destination C:\Temp\lab\ -ToSession $s
Invoke-Command -Session $s -ScriptBlock { & C:\Temp\lab\New-LabBaseImage.ps1 -IsoPath 'D:\ISOtools\Win11t.iso' -Index $using:idx -OutVhdx 'D:\HypVMs\tf-images\win11-base.vhdx' -AdminPassword $using:pw }
```

It takes roughly 10 to 20 minutes, mostly in `Expand-WindowsImage`. Do not close the window. The last lines show the disk as `Dynamic` with its size and file size, and it is read-only now.

---

## Part D: VM factory with PowerShell (40 min)

**D1. Create `New-LabVm.ps1`** next to the other script:

```powershell
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$ParentVhdx,
  [Parameter(Mandatory)][string]$SwitchName,
  [string]$VmRoot = 'D:\HypVMs\tf-vms',
  [int]$MemoryGB = 4,
  [int]$CpuCount = 2
)

$ErrorActionPreference = 'Stop'

# Safety rules
if ($Name -notlike 'tf-*') { throw "VM name must start with 'tf-'" }
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM '$Name' already exists" }
if (-not (Test-Path $ParentVhdx)) { throw "Parent disk not found: $ParentVhdx" }
$dir = Join-Path $VmRoot $Name
if (Test-Path $dir) { throw "Folder already exists: $dir" }

# Differencing disk: only the changes are stored, the parent stays untouched
New-Item -ItemType Directory -Path $dir | Out-Null
$vhd = Join-Path $dir "$Name.vhdx"
New-VHD -Path $vhd -ParentPath $ParentVhdx -Differencing | Out-Null

# Gen2 VM with Secure Boot and a virtual TPM
New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -VHDPath $vhd -SwitchName $SwitchName -Path $VmRoot | Out-Null
Set-VMProcessor -VMName $Name -Count $CpuCount
Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector
Enable-VMTPM -VMName $Name
Set-VM -Name $Name -AutomaticCheckpointsEnabled $false

Start-VM -Name $Name
Get-VM -Name $Name | Select-Object Name, State, Generation
```

Why these lines: the TPM needs a **key protector** first, which is why `Set-VMKeyProtector` comes before `Enable-VMTPM`. A local key protector means the VM cannot simply be moved to another host without its keys (fine in a lab). Automatic checkpoints are off so no hidden checkpoint grows beside the disk.

**D2. Build the first VM.** Replace `<SWITCH>` with the switch name from B1:

```powershell
$sw = '<SWITCH>'
"[$sw]"
Copy-Item .\New-LabVm.ps1 -Destination C:\Temp\lab\ -ToSession $s
Invoke-Command -Session $s -ScriptBlock { & C:\Temp\lab\New-LabVm.ps1 -Name tf-w11-01 -ParentVhdx 'D:\HypVMs\tf-images\win11-base.vhdx' -SwitchName $using:sw }
```

Expect the VM as `Running`, `Generation 2`. Check the TPM and the disk chain:

```powershell
Invoke-Command -Session $s -ScriptBlock { Get-VMSecurity -VMName tf-w11-01 | Select-Object TpmEnabled, Shielded }
Invoke-Command -Session $s -ScriptBlock { Get-VHD D:\HypVMs\tf-vms\tf-w11-01\tf-w11-01.vhdx | Select-Object VhdType, ParentPath, FileSize }
```

Expect `TpmEnabled True`, `VhdType Differencing`, the parent path and a small file size.

**D3. Wait for the first boot** (3 to 8 minutes: specialize pass, setup, autologon, WinRM). Check every minute or two:

```powershell
Invoke-Command -Session $s -ScriptBlock { Get-VM -Name tf-w11-01 | Select-Object State, Uptime, Status | Format-List }
Invoke-Command -Session $s -ScriptBlock { (Get-VMNetworkAdapter -VMName tf-w11-01).IPAddresses }
```

When an IPv4 address appears, the guest is up (this also proves the Hyper-V integration services work). Then from the workstation:

```powershell
$vmip = "<THE-IPV4>"
Test-NetConnection $vmip -Port 5985
```

`TcpTestSucceeded True` means WinRM is on. Write down how many minutes the first boot took.

To **see the screen** if something looks wrong, open the VM console: RDP to the host and open Hyper-V Manager, or run `vmconnect.exe 192.168.88.200 tf-w11-01` if your workstation has the Hyper-V tools. If you see a setup screen asking for a Microsoft account or language, the answer file was not used: tell me what the screen says.

---

## Part E: Ansible over WinRM (30 min, should do)

Same method as Day 2, new guest. In `day4-hyperv-factory\` create **`inventory.ini`** (it is in `.gitignore`):

```ini
[w11]
THE-IPV4 vm_hostname=TFW11-01

[w11:vars]
ansible_user=labadmin
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_port=5985
ansible_winrm_scheme=http
```

Replace `THE-IPV4` with the address from D3. Then **`w11.yml`**:

```yaml
---
- name: Configure the Windows 11 lab VM
  hosts: w11

  tasks:
    - name: Set the computer name
      ansible.windows.win_hostname:
        name: "{{ vm_hostname }}"
      register: rename

    - name: Reboot if the rename needs it
      ansible.windows.win_reboot:
      when: rename.reboot_required

    - name: Create the lab folder
      ansible.windows.win_file:
        path: C:\lab
        state: directory

    - name: Write a marker file
      ansible.windows.win_copy:
        dest: C:\lab\info.txt
        content: |
          Built by Hyper-V, configured by Ansible.

    - name: Read TPM and Secure Boot state
      ansible.windows.win_powershell:
        script: |
          [pscustomobject]@{
            TpmPresent = (Get-Tpm).TpmPresent
            TpmReady   = (Get-Tpm).TpmReady
            SecureBoot = Confirm-SecureBootUEFI
          }
      register: hw
      changed_when: false

    - name: Show the result
      ansible.builtin.debug:
        var: hw.output
```

Put the password on the clipboard without showing it (in PowerShell):

```powershell
$pw = (Import-Clixml "$env:USERPROFILE\lab-labadmin.cred.xml").GetNetworkCredential().Password
$pw | Set-Clipboard
```

In WSL, paste it between the single quotes (shell variables do not survive a new session):

```bash
path=/mnt/d/GITlabs/infra-learning-lab/07-azure/day4-hyperv-factory
export WIN_PASS='PASTE-HERE'

# 1. Reachable?
ansible -i $path/inventory.ini w11 -m ansible.windows.win_ping -e "ansible_password=$WIN_PASS"

# 2. Real run (renames the machine, so expect a reboot and a reconnect)
ansible-playbook -i $path/inventory.ini $path/w11.yml -e "ansible_password=$WIN_PASS"

# 3. Second run: idempotency
ansible-playbook -i $path/inventory.ini $path/w11.yml -e "ansible_password=$WIN_PASS"
```

Expected: `pong` for step 1, `changed` for the rename, the folder and the file in step 2, and **no changes** in step 3. The debug output in step 2 shows whether the VM really has a TPM and Secure Boot, which is what the Intune days need. If the `--check` mode fails on the reboot or rename tasks, it is the same dry-run limit as on Day 1 and not a broken playbook.

**Experiment (should do, 5 min): is the password still in the guest?** Run in WSL:

```bash
ansible -i $path/inventory.ini w11 -m ansible.windows.win_shell -a "Select-String -Path C:\Windows\Panther\unattend.xml -Pattern 'PlainText' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count" -e "ansible_password=$WIN_PASS"
```

Write down the number. I do not know whether Windows removes the answer file or its passwords after setup, so record what you see: `0` or an error means it was cleaned, and any number above `0` means the password is still lying around in the guest. Either way the base disk itself keeps the plain password (production note: Autopilot or LAPS, not baked passwords).

---

## Part F: The same VM with Terraform (60 min, gated)

This part uses a community provider. I could not open its registry page when I wrote this plan, so **the provider arguments below are from my memory of its documentation and not checked**. `terraform validate` is the judge: paste me the exact error and we fix it. The provider is `taliesins/hyperv` (registry page: `registry.terraform.io/providers/taliesins/hyperv`). Its GitHub issue list shows little recent activity, which is a risk to note for production.

**F0. The gate (10 min).** Open the provider documentation for the resource `hyperv_machine_instance` and look for **TPM** (search the page for `tpm`).

- **TPM argument exists:** use it in the VM resource below, and Terraform builds the same VM as the script.
- **No TPM argument:** build the Terraform VM **without** a TPM. That is still a valid IaC lesson (disk chain, VM, network from code), and the Intune VMs come from the PowerShell factory. Record "provider cannot set vTPM" as a finding.

Tell me the result before you build, so I can adjust the files.

**F1. Files in `day4-hyperv-factory\terraform\`.** Copy the backend from Part 1 with a new state key:

```powershell
mkdir terraform
cd terraform
Copy-Item ..\..\day4-entra-id\backend.tf .
(Get-Content .\backend.tf) -replace 'day4-entra\.tfstate','day4-hyperv.tfstate' | Set-Content .\backend.tf
Select-String .\backend.tf -Pattern 'key'
```

The last line must show `day4-hyperv.tfstate`. Terraform's remote state needs your Azure login (`adm.lab` via `az login`), same as the other days.

**`variables.tf`**
```hcl
variable "hyperv_host" {
  type = string
}

variable "switch_name" {
  type = string
}

variable "parent_vhdx" {
  type    = string
  default = "D:\\HypVMs\\tf-images\\win11-base.vhdx"
}

variable "vm_root" {
  type    = string
  default = "D:\\HypVMs\\tf-vms"
}
```

**`main.tf`**
```hcl
terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }
}

provider "hyperv" {
  host     = var.hyperv_host
  port     = 5985
  https    = false
  insecure = true
  use_ntlm = true
  timeout  = "60s"
  # user and password are NOT written here: they come from the environment
}

resource "hyperv_vhd" "os" {
  path        = "${var.vm_root}\\tf-w11-02.vhdx"
  vhd_type    = "Differencing"
  parent_path = var.parent_vhdx
}

resource "hyperv_machine_instance" "w11" {
  name                 = "tf-w11-02"
  generation           = 2
  processor_count      = 2
  static_memory        = true
  memory_startup_bytes = 4294967296

  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = "MicrosoftWindows"
  }

  network_adaptors {
    name        = "nic"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.os.path
  }
}
```

Add the TPM argument from F0 inside `hyperv_machine_instance` if the provider has one. **`terraform.tfvars`** (it is in `.gitignore`):

```hcl
hyperv_host = "192.168.88.200"
switch_name = "<SWITCH>"
```

**F2. Credentials through the environment**, so they never reach a file, the state or the chat:

```powershell
$env:HYPERV_USER     = $cred.UserName
$env:HYPERV_PASSWORD = $cred.GetNetworkCredential().Password
```

(`$cred` is from Part A2. If the plan complains that the user is missing, the variable names are different in your provider version: tell me.)

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
```

- `init` must say `Successfully configured the backend "azurerm"` and install `taliesins/hyperv`.
- Expect **`Plan: 2 to add, 0 to change, 0 to destroy`** (the disk and the VM). Nothing existing on the host can show up here, because Terraform only knows what is in its own state.
- `terraform apply`, then check on the host: `Invoke-Command -Session $s -ScriptBlock { Get-VM | Select-Object Name, State }` shows `tf-w11-02` next to your other VMs.
- Find its IP as in D3 (`Get-VMNetworkAdapter -VMName tf-w11-02`), add a second line to `inventory.ini` with `vm_hostname=TFW11-02`, and run the same playbook against it. This is the full chain: Terraform builds, Ansible configures.

**Things worth understanding.** The provider sends PowerShell to the host over WinRM, the same remoting as the scripts. `hyperv_vhd` with `vhd_type = Differencing` is the code form of `New-VHD -Differencing`. Because the base disk already contains the answer file, Terraform needs no per-VM injection step, which is why we built the factory this way.

---

## Part G: Teardown and verify (15 min)

Terraform VM first, then the script VM:

```powershell
terraform plan -destroy
terraform destroy
cd ..
Invoke-Command -Session $s -ScriptBlock { Stop-VM -Name tf-w11-01 -TurnOff -Force; Remove-VM -Name tf-w11-01 -Force; Remove-Item D:\HypVMs\tf-vms\tf-w11-01 -Recurse -Force }
```

- `plan -destroy` must list **2** resources.
- Do not remove anything that does not start with `tf`.

Verify:

```powershell
Invoke-Command -Session $s -ScriptBlock { Get-VM | Select-Object Name, State | Format-Table -AutoSize }
Invoke-Command -Session $s -ScriptBlock { Get-ChildItem D:\HypVMs -Recurse -Filter *.vhdx | Select-Object FullName, @{n='GB';e={[math]::Round($_.Length/1GB,1)}} | Format-Table -AutoSize }
Invoke-Command -Session $s -ScriptBlock { Get-ChildItem D:\HypVMs\tf-vms | Select-Object Name }
```

- Only `W11-LAB01` (in the state it had in B1) may remain, **plus the base disk** `D:\HypVMs\tf-images\win11-base.vhdx`.
- `D:\HypVMs\tf-vms` must be empty. If `terraform destroy` left a `.vhdx` behind, delete that file by name and write it down.
- **The base disk stays**: it is the starting point for the Intune days. It is read-only, never booted and not joined to anything.

Finally close the session and remove the helper files from the host:

```powershell
Invoke-Command -Session $s -ScriptBlock { Remove-Item C:\Temp\lab -Recurse -Force }
Remove-PSSession $s
Remove-Item Env:HYPERV_USER, Env:HYPERV_PASSWORD -ErrorAction SilentlyContinue
```

Commit the scripts, the playbook and the Terraform files, never `terraform.tfvars`, `inventory.ini` or anything with a password.

---

## Part H: What to send me at the end

1. Part A: whether the remoting worked at once or which fix it needed (TrustedHosts, `Enable-PSRemoting`).
2. Part B: the VM list, the switch name, free GB on `D:`, free GB of RAM, and the edition table of the ISO (index, name, size) plus the index you chose.
3. Part C: how long the base build took, the disk size at the end, and any error from the script.
4. Part D: `TpmEnabled`, the differencing disk size, how many minutes the first boot took, and whether the IP appeared.
5. Part E: the `win_ping` result, the `PLAY RECAP` lines of runs 2 and 3, the TPM/Secure Boot debug output, and the number from the password experiment.
6. Part F: the answer to the F0 gate (does the provider have a TPM argument), the `Plan:` line, and the exact errors if `validate` or `apply` failed.
7. Part G: the destroy count and the final VM and disk lists.
8. Any errors and how you fixed them. **Do not paste the host or VM passwords, `$cred`, the cred file, or the host's account name.**

---

## Priority if time runs short

- **Must do:** Parts A, B, C, D, G. The base disk and one VM from it are what the Intune days need.
- **Should do:** Part E (Ansible) and its password experiment.
- **Nice to have:** Part F (Terraform, gated). It can move to a quiet slot. The ISO for Windows 10 is not needed today.

## Likely problems

| Symptom | Likely cause | What to do |
|---|---|---|
| `Test-WSMan` or `New-PSSession` fails with a trust or access error | Host not in a domain, TrustedHosts empty, or remoting off | See A1: `Enable-PSRemoting` on the host, TrustedHosts on the workstation |
| `Test-Path D:\ISOtools\Win11t.iso` is `False` on the host | The ISO is on the workstation's `D:` | Tell me, we copy it with `Copy-Item -ToSession` |
| Base script fails at the boot partition drive letter | Windows will not give an EFI partition a letter this way | Paste the exact error, delete the half-built `win11-base.vhdx` first |
| Base script fails midway | Disk left mounted or half built | `Dismount-VHD`, delete the half-built file by name, rerun. The script refuses to overwrite |
| VM boots into a Windows setup screen (language, account, EULA) | The answer file was not read or has a mistake | Describe the screen, check that `C:\Windows\Panther\unattend.xml` exists in the base disk |
| VM stuck on a UEFI shell or "no bootable device" | Boot partition or `bcdboot` step failed | Check the `bcdboot` output of the base build, rebuild the base |
| `Set-VM -AutomaticCheckpointsEnabled` is not found | Older Hyper-V module | Remove that line, tell me |
| No IP address in D3 after 10 minutes | The switch has no DHCP, or the guest has not finished | Open the console, check the switch name and that the router's DHCP serves the LAN |
| Port 5985 closed but the VM has an IP | `FirstLogonCommands` did not run | Log in on the console as `labadmin` and run `Enable-PSRemoting -Force -SkipNetworkProfileCheck` |
| `win_ping` authentication error | Wrong password pasted, or the guest still setting up | Re-read the password from the cred file, wait a few minutes |
| `Access is denied` for `labadmin` over WinRM | `LocalAccountTokenFilterPolicy` was not set | Set it by hand in the guest console, tell me |
| Terraform `validate` rejects an argument | The provider arguments are from memory | Paste the exact error, we check against the provider docs |
| Terraform cannot connect to the host | Wrong environment variable names or NTLM setting | Tell me which provider version `init` installed and the error text |
| A VM from the script is left over | Teardown forgotten | Run the Part G commands for that VM name only |
