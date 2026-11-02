
resource "microsoft365_graph_beta_device_management_windows_update_ring" "day6" {
  active_hours_end        = "18:00:00"
  active_hours_start      = "08:00:00"
  allow_windows11_upgrade = false
  assignments = [
    {
      filter_type = "none"
      group_id    = var.test_group_id
      type        = "groupAssignmentTarget"
    },
  ]
  automatic_update_mode                   = "autoInstallAndRebootAtMaintenanceTime"
  business_ready_updates_only             = "userDefined"
  description                             = "Day 6 test"
  display_name                            = "tf-ring-day6"
  drivers_excluded                        = false
  feature_updates_deferral_period_in_days = 30
  feature_updates_paused                  = false
  feature_updates_rollback_window_in_days = 10
  microsoft_update_service_allowed        = true
  quality_updates_deferral_period_in_days = 7
  quality_updates_paused                  = false
  role_scope_tag_ids                      = ["0"]
  skip_checks_before_restart              = false
  timeouts                                = null
  update_notification_level               = "defaultNotifications"
  user_pause_access                       = "enabled"
  user_windows_update_scan_access         = "enabled"
}

resource "microsoft365_graph_beta_device_management_settings_catalog_configuration_policy" "day6" {
  assignments = [
    {
      filter_type = "none"
      group_id    = var.test_group_id
      type        = "groupAssignmentTarget"
    },
  ]
  configuration_policy = {
    settings = [
      {
        id = "0"
        setting_instance = {
          choice_setting_collection_value     = null
          choice_setting_value                = null
          group_setting_collection_value      = null
          odata_type                          = "#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance"
          setting_definition_id               = "device_vendor_msft_policy_config_localpoliciessecurityoptions_interactivelogon_messagetextforusersattemptingtologon"
          setting_instance_template_reference = null
          simple_setting_collection_value = [
            {
              odata_type                       = "#microsoft.graph.deviceManagementConfigurationStringSettingValue"
              setting_value_template_reference = null
              value                            = "Test device, managed by Intune (day 6, v3)"
            },
          ]
          simple_setting_value = null
        }
      },
      {
        id = "1"
        setting_instance = {
          choice_setting_collection_value     = null
          choice_setting_value                = null
          group_setting_collection_value      = null
          odata_type                          = "#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance"
          setting_definition_id               = "device_vendor_msft_policy_config_localpoliciessecurityoptions_interactivelogon_messagetitleforusersattemptingtologon"
          setting_instance_template_reference = null
          simple_setting_collection_value     = null
          simple_setting_value = {
            odata_type                       = "#microsoft.graph.deviceManagementConfigurationStringSettingValue"
            setting_value_template_reference = null
            value                            = "Lab notice"
            value_state                      = null
          }
        }
      },
    ]
  }
  description        = "Day 6 test"
  name               = "tf-cfg-win-day6"
  platforms          = "windows10"
  role_scope_tag_ids = ["0"]
  technologies       = ["mdm"]
  template_reference = {
  }
  timeouts = null
}

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
