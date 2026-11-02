terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }
}

provider "hyperv" {
  host     = var.hyperv_host
  port     = 5985
  https    = false
  insecure = true
  use_ntlm = true
  timeout  = "60s"
  # user and password are NOT written here: they come from the environment
}

resource "hyperv_vhd" "os" {
  path        = "${var.vm_root}\\tf-w11-02.vhdx"
  vhd_type    = "Differencing"
  parent_path = var.parent_vhdx
}

resource "hyperv_machine_instance" "w11" {
  name                 = "tf-w11-02"
  generation           = 2
  processor_count      = 2
  static_memory        = true
  memory_startup_bytes = 4294967296

  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = "MicrosoftWindows"
  }

  network_adaptors {
    name        = "nic"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.os.path
  }
}
