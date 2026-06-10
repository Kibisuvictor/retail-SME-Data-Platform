# ─────────────────────────────────────────────────────────
# variables.tf
# All input variables for the retail data platform.
# Fill in terraform.tfvars — never commit that file.
# ─────────────────────────────────────────────────────────

variable "project_id" {
  description = "Your GCP project ID (not the display name — the ID)."
  type        = string

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region for Cloud Scheduler and other regional resources."
  type        = string
  default     = "europe-west1"  # Closest to Kenya with full feature support
}

variable "bq_location" {
  description = "BigQuery dataset location. EU recommended for GDPR alignment."
  type        = string
  default     = "EU"

  validation {
    condition     = contains(["EU", "US", "asia-east1", "europe-west2"], var.bq_location)
    error_message = "bq_location must be EU, US, asia-east1, or europe-west2."
  }
}

variable "google_sheet_id" {
  description = "ID of the Google Sheet (from the URL: /spreadsheets/d/THIS_PART/edit)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.google_sheet_id) > 20
    error_message = "google_sheet_id looks too short — check the Sheet URL."
  }
}

variable "dataset_raw" {
  description = "BigQuery dataset name for raw external tables."
  type        = string
  default     = "retail_raw"
}

variable "dataset_staging" {
  description = "BigQuery dataset name for dbt staging models."
  type        = string
  default     = "retail_staging"
}

variable "dataset_marts" {
  description = "BigQuery dataset name for dbt mart models."
  type        = string
  default     = "retail_marts"
}

variable "dbt_runner_email" {
  description = <<-EOT
    Email address of the person or service account that runs dbt.
    This identity gets BigQuery Data Editor on staging and marts,
    and BigQuery Data Viewer on raw.
    Use your own Google email for local development.
    Example: victor@gmail.com
  EOT
  type        = string
}

variable "dashboard_viewer_emails" {
  description = <<-EOT
    List of emails that can view BigQuery data in Looker Studio.
    Include the business owner's email.
    Example: ["owner@gmail.com", "manager@gmail.com"]
  EOT
  type        = list(string)
  default     = []
}

variable "dbt_schedule" {
  description = "Cron schedule for daily dbt run (UTC). Default = 03:00 UTC = 06:00 EAT."
  type        = string
  default     = "0 3 * * *"
}

variable "environment" {
  description = "Deployment environment tag: dev or prod."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}
