# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform
resource "microsoft365_graph_beta_device_management_windows_platform_script" "day5" {
  assignments = [
    {
      group_id = "82f57c04-f9d4-4cec-adfa-5029de10fbeb"
      type     = "groupAssignmentTarget"
    },
  ]
  display_name            = "tf-ps-day5-marker"
  enforce_signature_check = false
  file_name               = "tf-ps-day5-marker.ps1"
  role_scope_tag_ids      = ["0"]
  run_as_32_bit           = false
  run_as_account          = "system"
  timeouts                = null
  script_content = file("${path.module}/../../day5-intune-enrollment/tf-ps-day5-marker.ps1")
}
