New-Item -ItemType Directory -Force -Path C:\ProgramData\lab | Out-Null
"Deployed by Intune v2 on $(Get-Date -Format s)" | Set-Content -Path C:\ProgramData\lab\day5-intune.txt
