# One identity per component. Each gets only the permissions it needs, granted next to
# the resource it needs them on.
resource "google_service_account" "web" {
  account_id   = "${local.app}-web"
  display_name = "Notely page (no permissions: it only forwards requests)"
}

resource "google_service_account" "api" {
  account_id   = "${local.app}-api"
  display_name = "Notely API"
}
