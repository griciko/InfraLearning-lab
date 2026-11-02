# AWS — Day 3: Review Q&A

Notes from the review session after building a Windows Server instance with Terraform, moving state into a versioned S3 backend, and handling a partially failed apply.

---

### 1. Why can't Terraform create the S3 bucket that holds its own state, and how was that solved?

The state backend has to exist before Terraform can store anything in it, so the same Terraform project can't both create the bucket and depend on it for its own state. This is a chicken-and-egg problem, usually called bootstrapping. It was solved by creating the bucket once with the AWS CLI, outside the project, with versioning and public-access blocking enabled. After that, a `backend "s3"` block was added to the project and `terraform init -migrate-state` copied the existing local state into the bucket.

---

### 2. What problems does remote state solve compared to a `.tfstate` file on a laptop?

A local state file can be lost, deleted, or edited by accident, can't be shared with teammates or pipelines, and has no locking, so two simultaneous `apply` runs can corrupt it. It also contains resource attributes, sometimes including secrets, in plain JSON. Remote state in S3 addresses these: the file lives in durable storage, can be shared, is protected against concurrent runs by locking (`use_lockfile = true`), and is kept in a private, encrypted bucket with versioning. Remote state does not remove secrets from the state file. It protects where they are stored, using encryption and IAM access control instead of a loose file on a laptop or in Git.

---

### 3. The apply failed on the instance type. What had already been created, and why was re-running `apply` enough?

Terraform does not roll back a failed apply. It creates resources in dependency order and keeps everything that already succeeded. The security group, which has no dependencies, was created and recorded in state. The instance, rejected by AWS because `t3.medium` is not available on the Free Tier account, was not. Resources independent of the instance, such as the SNS notification chain, were created as well. After changing the instance type to `c7i-flex.large`, re-running `apply` was enough because Terraform compares the code against the state: the state already held the security group, the code wanted the security group plus the instance, so the only difference was the instance. This is the same reconciliation model learned in Week 1. Also worth remembering: `plan` passed while `apply` failed, because `plan` can't know account-level restrictions. Only the real API call finds those out. `terraform state list` shows what is currently tracked after a failure.

---

### 4. Why does one session produce several state versions in S3, and what does versioning give you?

A new version is created whenever the state is written, not on every command (a plain `plan` doesn't write state). In this session writes came from the migration, the failed apply, the corrected apply, the stop/start re-apply, the SNS apply, and the destroy. With native locking, small `.tflock` lock objects are written and removed during each operation and also show up in the version list, so entries ending in `.tflock` are locks and the rest are real state history.

Versioning gives **recovery** more than just tracking: the ability to roll back to an earlier state file if one is corrupted, overwritten, or deleted by mistake, plus an audit trail of when the state changed. The state is the one file Terraform can't rebuild from code alone, since losing it means Terraform forgets what it built, so a history of it is cheap insurance.

---

### 5. Why did Windows need an RSA key pair, while the Linux instance worked with ED25519?

The key file does not contain the Windows password. On first boot, Windows generates a random Administrator password, AWS encrypts it with the **public** half of the key pair and stores the encrypted result, and the **private** `.pem` is used to decrypt it. That is public-key encryption, which RSA supports. ED25519 is a signature-only algorithm: it can prove identity, which is all SSH needs, but it can't encrypt and decrypt data, so AWS can't use it for Windows password retrieval. On Linux the key is the login itself, with no password involved. Once the password is decrypted, the RDP login uses the username and password and does not touch the key again.

---

*Lab covered: Windows Server AMI lookup via data source, RDP-only security group, explicit root disk with delete-on-terminate, S3 bucket bootstrap via CLI (versioning, public-access block, default encryption), state migration with `init -migrate-state`, native S3 locking, partial-failure behavior and recovery, Windows password decryption with RSA keys, state version history, and the state file's contents after destroy.*
