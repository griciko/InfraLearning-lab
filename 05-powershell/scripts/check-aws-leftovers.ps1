# ---------- check-aws-leftovers.ps1 ----------
# Lists AWS resources that keep costing money after a lab session. Read-only: it never deletes anything.
# Exit code: 0 = clean, 1 = leftovers found, 2 = pre-flight or a check failed.

# ---------- Input: which region to check (default: eu-north-1) ----------
param(
    [string]$Region = "eu-north-1"
)

# ---------- Stop on errors, so try/catch can handle them ----------
$ErrorActionPreference = "Stop"

# ---------- Helper: run an AWS CLI command and return the result as objects ----------
function Invoke-AwsJson {
    param([string[]]$CliArgs)

    # Run the CLI. Splatting (@) passes each array item as a separate argument
    $raw = & aws @CliArgs --region $Region --output json

    # Native commands do not throw on failure, so check the exit code ourselves
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI failed (exit code $LASTEXITCODE): aws $($CliArgs -join ' ')"
    }

    # Nothing returned means nothing found
    if (-not $raw) { return @() }

    # Join the output lines and convert the JSON text into PowerShell objects
    return ($raw -join "`n") | ConvertFrom-Json
}

# ---------- Helper: confirm the CLI exists and is authenticated ----------
function Test-AwsReady {
    # Is the AWS CLI installed?
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw "AWS CLI not found. Install it first."
    }

    # Who am I? This also proves the credentials work
    $identity = Invoke-AwsJson -CliArgs @("sts", "get-caller-identity")

    # Show only the last 4 digits of the account ID, so screenshots stay safe
    $maskedAccount = ("*" * 8) + $identity.Account.Substring(8)
    Write-Host "Account: $maskedAccount | Region: $Region" -ForegroundColor Gray
}

# ---------- The checks: a name plus the CLI arguments for each ----------
$checks = @(
    @{
        Name    = "EC2 instances (pending, running, stopping, stopped)"
        CliArgs = @("ec2", "describe-instances",
            "--filters", "Name=instance-state-name,Values=pending,running,stopping,stopped",
            "--query", "Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key=='Name']|[0].Value}")
    },
    @{
        Name    = "Unattached EBS volumes"
        CliArgs = @("ec2", "describe-volumes",
            "--filters", "Name=status,Values=available",
            "--query", "Volumes[].{Id:VolumeId,SizeGB:Size,Created:CreateTime}")
    },
    @{
        Name    = "EBS snapshots owned by this account"
        CliArgs = @("ec2", "describe-snapshots", "--owner-ids", "self",
            "--query", "Snapshots[].{Id:SnapshotId,SizeGB:VolumeSize,Started:StartTime,Name:Tags[?Key=='Name']|[0].Value}")
    },
    @{
        Name    = "AMIs owned by this account"
        CliArgs = @("ec2", "describe-images", "--owners", "self",
            "--query", "Images[].{Id:ImageId,Name:Name,Created:CreationDate}")
    },
    @{
        Name    = "Elastic IPs not attached to anything"
        CliArgs = @("ec2", "describe-addresses",
            "--query", "Addresses[?AssociationId==null].{Ip:PublicIp,AllocationId:AllocationId}")
    }
)

# ---------- Pre-flight: stop early if the CLI or credentials are not ready ----------
try {
    Test-AwsReady
}
catch {
    Write-Host "Pre-flight failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

# ---------- Run every check and count what was found ----------
$totalFound = 0
$failedChecks = 0

foreach ($check in $checks) {
    Write-Host ""
    Write-Host "=== $($check.Name)" -ForegroundColor Cyan

    try {
        # @() forces an array, even when the result is a single object or nothing
        $items = @(Invoke-AwsJson -CliArgs $check.CliArgs)
    }
    catch {
        Write-Host "  CHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failedChecks++
        continue    # skip to the next check
    }

    if ($items.Count -eq 0) {
        Write-Host "  none found" -ForegroundColor Green
    }
    else {
        Write-Host "  $($items.Count) found" -ForegroundColor Yellow
        # Format-Table builds a table, Out-String turns it into text, Write-Host prints it
        $items | Format-Table -AutoSize | Out-String | Write-Host
        $totalFound += $items.Count
    }
}

# ---------- Summary and exit code ----------
Write-Host ""
Write-Host "-----------------------------------------"
if ($failedChecks -gt 0) {
    Write-Host "RESULT: $failedChecks check(s) failed, the report is incomplete" -ForegroundColor Red
    exit 2
}
elseif ($totalFound -eq 0) {
    Write-Host "RESULT: CLEAN, nothing left behind" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "RESULT: $totalFound leftover item(s) found, review the list above" -ForegroundColor Yellow
    exit 1
}

