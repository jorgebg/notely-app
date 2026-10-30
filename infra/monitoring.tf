# Every minute, from three regions, ask the page for /health. The page forwards it to the
# API, which runs SELECT 1: one probe covers the path a user takes.
resource "google_monitoring_uptime_check_config" "page" {
  display_name     = "Notely page /health"
  period           = "60s"
  timeout          = "10s"
  selected_regions = ["USA_IOWA", "USA_OREGON", "USA_VIRGINIA"]

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = trimprefix(module.web.uri, "https://")
    }
  }
}

# Someone created this channel by hand in the console. Instead of creating a second one,
# adopt it: on the next apply Terraform records it in the state and manages it from then on.
import {
  to = google_monitoring_notification_channel.email
  id = var.notification_channel
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "Notely alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# The app is down: the uptime check fails from more than one region for 5 minutes.
resource "google_monitoring_alert_policy" "app_down" {
  display_name = "Notely is down"
  combiner     = "OR"

  conditions {
    display_name = "/health fails through the page"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.page.uptime_check_id}\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    content = "The page's /health has failed from more than one region for 5 minutes. It checks page -> API -> database."
  }
}
