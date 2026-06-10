# ─────────────────────────────────────────────────────────
# outputs.tf
# Values printed after terraform apply.
# Use these to configure dbt profiles.yml and GitHub Actions.
# ─────────────────────────────────────────────────────────

# ── Project info ──────────────────────────────────────────

output "project_id" {
  description = "GCP project ID."
  value       = var.project_id
}

output "bq_location" {
  description = "BigQuery dataset location."
  value       = var.bq_location
}

# ── BigQuery dataset IDs ──────────────────────────────────

output "dataset_raw" {
  description = "BigQuery raw dataset ID."
  value       = google_bigquery_dataset.raw.dataset_id
}

output "dataset_staging" {
  description = "BigQuery staging dataset ID. Configure this in dbt profiles.yml."
  value       = google_bigquery_dataset.staging.dataset_id
}

output "dataset_marts" {
  description = "BigQuery marts dataset ID."
  value       = google_bigquery_dataset.marts.dataset_id
}

# ── External table references ─────────────────────────────

output "external_tables" {
  description = "Fully qualified external table names for verifying in BigQuery console."
  value = {
    sales_raw                = "${var.project_id}.${var.dataset_raw}.sales_raw"
    expenses_raw             = "${var.project_id}.${var.dataset_raw}.expenses_raw"
    inventory_purchases_raw  = "${var.project_id}.${var.dataset_raw}.inventory_purchases_raw"
    products_raw             = "${var.project_id}.${var.dataset_raw}.products_raw"
    returns_raw              = "${var.project_id}.${var.dataset_raw}.returns_raw"
  }
}

# ── Service accounts ──────────────────────────────────────

output "dbt_service_account_email" {
  description = <<-EOT
    Email of the dbt runner service account.
    Use this for:
      1. GitHub Actions secret (GOOGLE_CREDENTIALS)
      2. Share your Google Sheet with this email as Viewer
  EOT
  value = google_service_account.dbt_sa.email
}

output "scheduler_service_account_email" {
  description = "Email of the Cloud Scheduler service account."
  value       = google_service_account.scheduler_sa.email
}

# ── Service account key for CI ────────────────────────────
# Used as a GitHub Actions secret (GOOGLE_CREDENTIALS).
# Sensitive — not shown in plain text in console output.

output "dbt_sa_key_base64" {
  description = <<-EOT
    Base64-encoded service account key for GitHub Actions.
    Copy this value and add it as a GitHub repository secret named GOOGLE_CREDENTIALS.
    To view: terraform output -raw dbt_sa_key_base64
  EOT
  value     = google_service_account_key.dbt_sa_key.private_key
  sensitive = true
}

# ── Pub/Sub topic ─────────────────────────────────────────

output "pubsub_topic_name" {
  description = "Pub/Sub topic that Cloud Scheduler publishes to."
  value       = google_pubsub_topic.dbt_trigger.name
}

output "scheduler_job_name" {
  description = "Cloud Scheduler job name."
  value       = google_cloud_scheduler_job.dbt_daily.name
}

# ── dbt profiles.yml snippet ──────────────────────────────
# Copy this into dbt_retail/profiles.yml

output "dbt_profiles_yml_snippet" {
  description = "Paste this into dbt_retail/profiles.yml (prod target section)."
  value       = <<-EOT

    prod:
      type: bigquery
      method: service-account
      project: ${var.project_id}
      dataset: ${google_bigquery_dataset.staging.dataset_id}
      location: ${var.bq_location}
      keyfile: /path/to/dbt-sa-key.json
      threads: 4
      timeout_seconds: 300
      priority: batch
      retries: 2

  EOT
}

# ── Next steps ────────────────────────────────────────────

output "next_steps" {
  description = "What to do after terraform apply."
  value       = <<-EOT

    ══════════════════════════════════════════════════════
    Terraform apply complete. Next steps:
    ══════════════════════════════════════════════════════

    1. Share your Google Sheet with the dbt service account:
       Email: ${google_service_account.dbt_sa.email}
       Permission: Viewer

    2. Add GitHub Actions secret:
       Name:  GOOGLE_CREDENTIALS
       Value: run → terraform output -raw dbt_sa_key_base64

    3. Add GitHub Actions secret:
       Name:  GCP_PROJECT_ID
       Value: ${var.project_id}

    4. Verify external tables in BigQuery console:
       ${var.project_id}.${var.dataset_raw}.sales_raw
       ${var.project_id}.${var.dataset_raw}.expenses_raw
       ${var.project_id}.${var.dataset_raw}.inventory_purchases_raw
       ${var.project_id}.${var.dataset_raw}.products_raw
       ${var.project_id}.${var.dataset_raw}.returns_raw

    5. Run dbt:
       cd dbt_retail
       dbt deps
       dbt seed --profiles-dir .
       dbt run  --profiles-dir .
       dbt test --profiles-dir .

    6. Connect Looker Studio:
       Go to lookerstudio.google.com
       Add BigQuery data source → ${var.project_id} → retail_marts
       Follow docs/looker_studio_setup.md

    ══════════════════════════════════════════════════════

  EOT
}
