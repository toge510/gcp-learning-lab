terraform {
  backend "gcs" {
    bucket = "tf-remote-state-backend-gcs"
    prefix = "dev-toge-001/security-policy/"
  }
}