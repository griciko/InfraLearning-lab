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
