# PDF attachments. Private: only the API reads and writes them.
resource "google_storage_bucket" "attachments" {
  name                        = "${var.project_id}-attachments"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # the demo ends with destroy; in real life: false
}

resource "google_storage_bucket_iam_member" "api_attachments" {
  bucket = google_storage_bucket.attachments.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.api.member
}
