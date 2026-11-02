$root = 'D:\GITlabs\infra-learning-lab\07-azure\day7-intune-code'
Push-Location (Join-Path $root 'auth')
$env:TF_VAR_client_id = terraform output -raw client_id
$env:TF_VAR_client_secret = terraform output -raw client_secret
Pop-Location
$tid = (Select-String -Path (Join-Path $root 'intune\terraform.tfvars') -Pattern 'tenant_id').Line.Split('"')[1]
function Update-Token {
  $body = @{ client_id = $env:TF_VAR_client_id; client_secret = $env:TF_VAR_client_secret; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' }
  $tok = (Invoke-RestMethod -Method Post -Uri ('https://login.microsoftonline.com/' + $tid + '/oauth2/v2.0/token') -Body $body).access_token
  $global:h = @{ Authorization = ('Bearer ' + $tok) }
}
Update-Token
$env:TF_VAR_client_secret.Length
