# Spending guard for the demo. Applied once, as yourself (NOT as terraform-runner, which has no
# access to the guard project), and never destroyed by the demo:
#
#   source infra/demo.env && unset GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
#   terraform -chdir=infra/offstage/guard init && terraform -chdir=infra/offstage/guard apply \
#     -var guard_project_id=$GUARD_PROJECT -var demo_project_id=$DEMO_PROJECT \
#     -var billing_account=$BILLING_ACCOUNT
#
# - A budget on the billing account, filtered to the demo and guard projects: e-mails the billing
#   admins at 50%, 90% and 100% of actual spend and 100% of forecast spend.
# - Every budget update goes to a Pub/Sub topic. A function reads it and, once the spend passes the
#   budget, disconnects billing from the demo project: everything there stops. Other projects keep
#   running. (Google's documented "cap costs" pattern.)
# - A pull subscription lets a script read the latest spend (check-spend.sh).
#
# Billing data arrives hours late: this catches a leak, it does not stop a spike as it happens.

terraform {
  required_version = ">= 1.11"
  required_providers {
    google  = { source = "hashicorp/google", version = "~> 8.7.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
}

variable "guard_project_id" { type = string }
variable "demo_project_id" { type = string }
variable "billing_account" { type = string }

variable "budget_eur" {
  type    = number
  default = 1
}

variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.guard_project_id
  region  = var.region
  # The Budget API bills its calls to a project: the guard's.
  user_project_override = true
  billing_project       = var.guard_project_id
}

data "google_project" "guard" { project_id = var.guard_project_id }
data "google_project" "demo" { project_id = var.demo_project_id }

resource "google_project_service" "apis" {
  for_each = toset([
    "billingbudgets.googleapis.com", "cloudbilling.googleapis.com", "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com", "run.googleapis.com", "cloudbuild.googleapis.com",
    "eventarc.googleapis.com", "artifactregistry.googleapis.com", "storage.googleapis.com",
    "logging.googleapis.com", "iam.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

resource "google_pubsub_topic" "budget" {
  name       = "budget-alerts"
  depends_on = [google_project_service.apis]
}

# Read by check-spend.sh before every apply of a rehearsal.
resource "google_pubsub_subscription" "check" {
  name                       = "budget-check"
  topic                      = google_pubsub_topic.budget.id
  message_retention_duration = "604800s"
}

resource "google_billing_budget" "demo" {
  billing_account = var.billing_account
  display_name    = "Notely demo (EUR ${var.budget_eur})"

  budget_filter {
    projects               = ["projects/${data.google_project.demo.number}", "projects/${data.google_project.guard.number}"]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(var.budget_eur)
    }
  }

  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic   = google_pubsub_topic.budget.id
    schema_version = "1.0"
  }

  depends_on = [google_project_service.apis]
}

# --- Kill switch -------------------------------------------------------------------------------

resource "google_service_account" "killswitch" {
  account_id   = "budget-killswitch"
  display_name = "Disconnects billing from the demo project when the budget is exceeded"
  depends_on   = [google_project_service.apis]
}

# Enough to unlink the demo project from its billing account, nothing more.
resource "google_project_iam_member" "killswitch_billing" {
  project = var.demo_project_id
  role    = "roles/billing.projectManager"
  member  = google_service_account.killswitch.member
}

resource "google_project_iam_member" "killswitch_invoker" {
  project = var.guard_project_id
  role    = "roles/run.invoker"
  member  = google_service_account.killswitch.member
}

resource "google_project_iam_member" "killswitch_events" {
  project = var.guard_project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.killswitch.member
}

# The function's build runs as its own identity, not the default compute account.
resource "google_service_account" "build" {
  account_id   = "killswitch-build"
  display_name = "Builds the kill switch function"
  depends_on   = [google_project_service.apis]
}

resource "google_project_iam_member" "build" {
  for_each = toset(["roles/logging.logWriter", "roles/artifactregistry.writer", "roles/storage.objectViewer"])
  project  = var.guard_project_id
  role     = each.value
  member   = google_service_account.build.member
}

resource "google_storage_bucket" "source" {
  name                        = "${var.guard_project_id}-killswitch-source"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  depends_on                  = [google_project_service.apis]
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

resource "google_storage_bucket_object" "function" {
  name   = "killswitch-${data.archive_file.function.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.function.output_path
}

resource "google_cloudfunctions2_function" "killswitch" {
  name     = "budget-killswitch"
  location = var.region

  build_config {
    runtime         = "python312"
    entry_point     = "stop_billing"
    service_account = google_service_account.build.id
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.function.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    service_account_email = google_service_account.killswitch.email
    environment_variables = { DEMO_PROJECT_ID = var.demo_project_id }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.budget.id
    service_account_email = google_service_account.killswitch.email
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
  }

  depends_on = [google_project_iam_member.build, google_project_iam_member.killswitch_events]
}

output "budget" { value = google_billing_budget.demo.display_name }
output "subscription" { value = google_pubsub_subscription.check.id }
