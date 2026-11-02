function Get-One($url, $prop, $name) {
  $r = @((Invoke-RestMethod -Headers $global:h -Uri $url).value | Where-Object { $_.$prop -eq $name })
  if ($r.Count -ne 1 -or $r[0].id.Length -ne 36) { throw ('not exactly one result for ' + $name) }
  $r[0].id
}
$b = 'https://graph.microsoft.com/beta/'
$ring = Get-One ($b + 'deviceManagement/deviceConfigurations?$select=id,displayName') 'displayName' 'tf-ring-day6'
$prof = Get-One ($b + 'deviceManagement/configurationPolicies?$select=id,name') 'name' 'tf-cfg-win-day6'
$scr  = Get-One ($b + 'deviceManagement/deviceManagementScripts?$select=id,displayName') 'displayName' 'tf-ps-day5-marker'
$grp = (az ad group show --group grp-tf-intune-test --query id -o tsv); if ($grp.Length -ne 36) { throw "group lookup failed" }
$lines = @(('ring_id = "{0}"' -f $ring), ('profile_id = "{0}"' -f $prof), ('script_id = "{0}"' -f $scr), ('test_group_id = "{0}"' -f $grp))
Set-Content (Join-Path $PSScriptRoot 'intune\ids.auto.tfvars') $lines
'ids written: ' + $lines.Count
