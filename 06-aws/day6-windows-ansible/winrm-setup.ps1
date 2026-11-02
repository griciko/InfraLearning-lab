# ---------- winrm-setup.ps1: enable WinRM over HTTPS for Ansible (lab) ----------
# Runs once, at first boot, through EC2 user data (EC2Launch v2).
# If WinRM does not work, check C:\ProgramData\Amazon\EC2Launch\log\agent.log

$ErrorActionPreference = "Stop"

# ---------- Make sure the WinRM service starts automatically and is running ----------
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# ---------- Create the base WinRM configuration if no listener exists yet ----------
if (-not (Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue)) {
    Enable-PSRemoting -SkipNetworkProfileCheck -Force
}

# ---------- Create a self-signed certificate for this host (valid 30 days, lab only) ----------
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddDays(30)

# ---------- Remove the plain HTTP listener, so only HTTPS remains ----------
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTP" } | Remove-Item -Recurse -Force

# ---------- Remove any old HTTPS listener, then create one with the new certificate ----------
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force

# ---------- Windows Firewall: allow inbound 5986 (the security group limits who can reach it) ----------
New-NetFirewallRule -DisplayName "WinRM HTTPS (Ansible lab)" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any