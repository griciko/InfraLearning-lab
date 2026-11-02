# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform
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
