resource "google_storage_bucket" "default" {
  name     = "tf-remote-state-backend-gcs"
  location = "ASIA-NORTHEAST1"

  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}