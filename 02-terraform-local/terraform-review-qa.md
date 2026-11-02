# Terraform Local Lab — Review Q&A

Notes from the review session after completing the local Terraform lab (local_file, random, modules, Docker/nginx).

---

### 1. What's the difference between what's tracked in your code vs. your state, and what happens if they disagree?

Code defines the **desired state** of the infrastructure — what I want to exist. State is Terraform's record of the **current state** of the resources it manages — what it believes actually exists. If the two disagree, Terraform reconciles the difference by creating, updating, or destroying resources so that reality matches the code. Code always wins; state is just Terraform's memory of where things stand.

---

### 2. What did the drift example — stopping the nginx container, then running `plan` — actually show you?

Drift means Terraform detected a difference between the desired state (code says the container should be running) and the actual state (the container was stopped). The container already existed — it wasn't recreated from nothing — so `plan` proposed bringing it back in line with the desired state (starting it again, or replacing it, depending on how the provider handles that specific attribute). The point isn't "create vs. not" — it's that Terraform noticed actual ≠ desired and proposed a fix to reconcile them. In a real environment (e.g. an Azure VM), this distinction matters a lot: a simple restart is harmless, but a forced recreate can mean data loss.

---

### 3. Why did removing a resource block from `main.tf` delete the real file, instead of Terraform just "forgetting" about it?

If a resource block is no longer in `main.tf`, Terraform doesn't ignore it — it treats anything that's in the state but missing from the code as **no longer desired**, and destroys it on the next apply. There's no middle ground like "leave it alone if I don't mention it." This is the key mental shift from imperative scripting (where not mentioning something means "don't touch it") to Terraform's declarative model (where not mentioning something means "this shouldn't exist"). To keep a resource, it must stay in the code.

---

### 4. What's the difference between a resource and a module — and why call the same module twice instead of writing the resource block twice?

A **resource** is a single object managed by a provider (one file, one container, one VM). A **module** is a reusable package containing one or more resources, with its own inputs and outputs. Calling the same module twice with different inputs keeps the code cleaner, avoids duplication, and makes it easy to reuse the same pattern across multiple environments (e.g. the same "VM module" called once for dev and once for prod) instead of copy-pasting resource blocks.

---

### 5. Why read a `plan -destroy` output just as carefully as a regular `plan`?

Because it describes real, often irreversible changes. A `plan -destroy` should be read like an approval request — confirming exactly what will be deleted — the same way a regular `plan` is read to confirm exactly what will be created or changed, since Terraform will not ask for confirmation again beyond the single `yes` prompt.

---

*Lab covered: local_file resource, state inspection, drift detection (file and live container), variables/outputs/tfvars, random provider with count, reusable modules, accidental resource deletion and recovery, Docker/nginx container lifecycle.*
