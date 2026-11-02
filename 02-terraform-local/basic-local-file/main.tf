terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# ---------- Step 1 & 4: variable-driven file ----------

variable "message" {
  description = "Content to write into the file"
  type        = string
  default     = "Default message - updated via PR"
}

resource "local_file" "hello" {
  filename = "${path.module}/hello.txt"
  content  = var.message
}

output "file_path" {
  value = local_file.hello.filename
}

# ---------- Step 5: random pets ----------

resource "random_pet" "names" {
  count  = 3
  length = 2
}

resource "local_file" "pets" {
  count    = 3
  filename = "${path.module}/pet-${count.index}.txt"
  content  = "My pet's name is ${random_pet.names[count.index].id}"
}
