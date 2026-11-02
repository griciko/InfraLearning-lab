**Terraform — Learning block (about 1 hour)**

**1. The core idea**

**Terraform** is declarative: you describe the end state you want, and Terraform figures out how to get there — create, change, or destroy resources as needed. You don't write step-by-step instructions like you would in a PowerShell script.

**2. The building blocks**
| Concept | What it is |
| ------- | ---------- |
| Provider	| A plugin that lets Terraform talk to a platform (Azure, Docker, local filesystem, random values, etc.) |
| Resource	| A single thing to create/manage — a file, a VM, a container |
| State	| A file (terraform.tfstate) where Terraform records what it has created, so it can compare "desired" vs "actual" |
| Variable	| An input, so code is reusable (variable "name" {}) |
| Output	| A value exposed after apply (e.g. an IP address, a generated password) |
| Data source	| Read-only lookup of something that already exists |
| Module	| A reusable, packaged group of resources |

**3. The workflow**
```
terraform init      # download providers, set up backend
terraform fmt        # auto-format code
terraform validate   # check syntax/logic
terraform plan        # preview changes — READ THIS before apply
terraform apply        # make the changes
terraform destroy      # tear everything down
```

**4. State, briefly**

Every time you apply, Terraform updates terraform.tfstate with what now exists. On the next plan, it compares:
```
"Your code  (desired)  ↔  State file  (what Terraform thinks exists)  ↔  Real world (actual)"
```
