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
