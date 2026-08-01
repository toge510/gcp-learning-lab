terraform {
  backend "gcs" {
    bucket = "tf-remote-state-backend-gcs"
    prefix = "backend-setup"
  }
}