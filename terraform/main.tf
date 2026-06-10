# ─────────────────────────────────────────────────────────
# main.tf
# Provider configuration and GCP API enablement.
# ─────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # ── Remote state (optional but recommended) ─────────────
  # Uncomment to store Terraform state in GCS instead of locally.
  # This allows multiple people to run Terraform safely.
  # Create the bucket manually first: gsutil mb gs://YOUR-PROJECT-tfstate
  #
  # backend "gcs" {
  #   bucket = "YOUR-PROJECT-tfstate"
  #   prefix = "retail-platform/state"
  # }
}

# ── Provider ──────────────────────────────────────────────
provider "google" {
  project = var.project_id
  region  = var.region

  # Uses Application Default Credentials.
  # Run: gcloud auth application-default login
  # No service account key file needed for local development.
}

# ── Enable required GCP APIs ──────────────────────────────
# These are idempotent — safe to apply multiple times.

resource "google_project_service" "bigquery" {
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false

  timeouts {
    create = "10m"
  }
}

resource "google_project_service" "sheets" {
  service            = "sheets.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "drive" {
  service            = "drive.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_scheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}
