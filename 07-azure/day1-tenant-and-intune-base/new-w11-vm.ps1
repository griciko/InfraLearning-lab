# ---------- new-w11-vm.ps1: create a Windows 11 lab VM on this Hyper-V host ----------
$ErrorActionPreference = "Stop"

# ---------- Settings: edit these ----------
$vmName   = "W11-LAB01"
$vmRoot   = "D:\HypVMs"
$isoPath  = "D:\ISOtools\Windows11.iso"       # the real file name of your ISO
$switch   = "Intel(R) Ethernet Connection (2) I219-LM - Virtual Switch"
$memory   = 4GB
$cpuCount = 2
$diskSize = 80GB

# ---------- Create the Generation 2 VM with a new dynamic disk ----------
New-VM -Name $vmName -Generation 2 -MemoryStartupBytes $memory -Path $vmRoot -NewVHDPath "$vmRoot\$vmName\$vmName.vhdx" -NewVHDSizeBytes $diskSize -SwitchName $switch

# ---------- Two vCPUs, fixed memory ----------
Set-VMProcessor -VMName $vmName -Count $cpuCount
Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false

# ---------- Windows 11 needs a virtual TPM and Secure Boot ----------
Set-VMKeyProtector -VMName $vmName -NewLocalKeyProtector
Enable-VMTPM -VMName $vmName
Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

# ---------- Attach the ISO and boot from it first ----------
Add-VMDvdDrive -VMName $vmName -Path $isoPath
Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMDvdDrive -VMName $vmName)

# ---------- Start the VM and open its console ----------
Start-VM -Name $vmName
vmconnect.exe localhost $vmName