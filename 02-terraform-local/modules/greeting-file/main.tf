variable "filename" {
  type = string
}

variable "message" {
  type = string
}

resource "local_file" "this" {
  filename = var.filename
  content  = var.message
}

output "path" {
  value = local_file.this.filename
}
