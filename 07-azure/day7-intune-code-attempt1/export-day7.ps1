$ErrorActionPreference = 'Stop'
$tid = (Select-String -Path .\intune\terraform.tfvars -Pattern 'tenant_id').Line.Split('"')[1]
$body = @{ client_id = $env:TF_VAR_client_id; client_secret = $env:TF_VAR_client_secret; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
$tok = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tid/oauth2/v2.0/token" -Body $body).access_token
$h = @{ Authorization = "Bearer $tok" }
$out = 'D:\Temp\export-day7'
New-Item -ItemType Directory -Force $out | Out-Null
$dm = 'https://graph.microsoft.com/beta/deviceManagement'
$am = 'https://graph.microsoft.com/beta/deviceAppManagement'

$c = (Invoke-RestMethod -Headers $h -Uri "$dm/deviceCompliancePolicies?`$select=id,displayName").value | Where-Object displayName -eq 'tf-comp-win-day5'
if (-not $c.id) { throw 'compliance policy not found' }
Invoke-RestMethod -Headers $h -Uri "$dm/deviceCompliancePolicies/$($c.id)?`$expand=scheduledActionsForRule,assignments" | ConvertTo-Json -Depth 20 | Set-Content "$out\tf-comp-win-day5.json"

$a = (Invoke-RestMethod -Headers $h -Uri "$am/mobileApps?`$select=id,displayName").value | Where-Object displayName -eq 'tf-app-7zip'
if (-not $a.id) { throw 'app not found' }
Invoke-RestMethod -Headers $h -Uri "$am/mobileApps/$($a.id)?`$expand=assignments" | ConvertTo-Json -Depth 20 | Set-Content "$out\tf-app-7zip.json"

Get-ChildItem $out | Select-Object Name, Length