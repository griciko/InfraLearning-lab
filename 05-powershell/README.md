## check-aws-leftovers.ps1

Read-only script that lists AWS resources which keep costing money after a lab session: EC2 instances (including stopped), unattached EBS volumes, snapshots, AMIs, and unattached Elastic IPs.

Usage: `.\scripts\check-aws-leftovers.ps1 [-Region eu-north-1]`

Exit codes: 0 = clean, 1 = leftovers found, 2 = pre-flight or a check failed.

**Lab vs. production:** this is a small personal tool for a lab account. Production environments use cost tooling, tagging policies, and scheduled cleanups instead of hand-run scripts, but admins do write small checks like this one.