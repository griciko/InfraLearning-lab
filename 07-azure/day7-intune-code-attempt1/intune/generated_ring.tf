# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform
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
