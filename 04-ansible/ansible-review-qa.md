# Ansible Lab — Review Q&A

Notes from the review session after completing the Ansible lab (inventory, ad-hoc commands, playbooks, variables, templates, handlers, `--check`, and error handling), run from WSL/Ubuntu.

---

### 1. What's the core difference between Terraform and Ansible in terms of what each one is responsible for?

Terraform is responsible for **provisioning and managing infrastructure** — creating the VM, the network, the resource itself. Ansible focuses on **configuring that infrastructure and deploying applications onto it** — installing packages, managing files and services, applying settings once the underlying resource already exists. In a typical real workflow, Terraform creates the machine and Ansible then configures what's running on it.

---

### 2. Why does Ansible have no equivalent of a `.tfstate` file — how does it decide whether something needs to change?

Ansible is stateless by design — it doesn't keep a persistent record of what it previously did, unlike Terraform's state file. Instead, it relies on **idempotency checked fresh on every run**: each module has its own built-in logic for comparing desired vs. actual (e.g. the `apt` module checks whether the package is already installed; the `copy` module compares file content/checksums). So there's no single generic "state" being compared — each task independently checks the live system at run time and only acts if something doesn't already match.

---

### 3. What does `become: true` actually do, and why did it cause permission errors later?

`become: true` enables **privilege escalation** — it makes Ansible run the task with elevated permissions (equivalent to using `sudo` directly). Anything created or modified while `become: true` is active ends up owned by root on disk, exactly as if the command had been run manually with `sudo`. This is why later attempts to edit or delete those files as a normal user failed with "Permission denied" — the files genuinely belonged to root, and cleaning them up required `sudo rm` to match how they were created.

---

### 4. What's the purpose of a handler, and why didn't it fire on the second playbook run?

A handler is a task that only runs when it's **notified** by another task — typically used for actions like restarting a service after a config file changes. A handler can be notified multiple times within the same playbook run, but it still only executes **once**, at the end of the play. It didn't fire on the second run of the template playbook because the templated file's content hadn't changed — the task that would `notify` it reported no change, so nothing triggered the handler.

---

### 5. What did `--check` show, and what's the closest Terraform equivalent?

`--check` runs the playbook in **dry-run mode** — it reports what *would* change without actually making any changes. It's the direct Ansible equivalent of `terraform plan` (and conceptually similar to PowerShell's `-WhatIf`): a safe way to preview the effect of a run before committing to it for real.

---

*Lab covered: inventory and `ansible_connection=local`, ad-hoc commands, playbooks with `become`, idempotency proven across repeated runs, variables, Jinja2 templates with Ansible facts, handlers and `notify`, `--check` dry-run mode, `ignore_errors`, and root-owned file cleanup from `become`-escalated tasks.*
