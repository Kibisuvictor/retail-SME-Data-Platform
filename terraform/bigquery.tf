# ─────────────────────────────────────────────────────────
# bigquery.tf
# Three BigQuery datasets and five external tables that
# read directly from Google Sheets tabs.
# Column names match your actual Google Forms headers exactly.
# ─────────────────────────────────────────────────────────

locals {
  sheet_base_url = "https://docs.google.com/spreadsheets/d/${var.google_sheet_id}"

  bq_labels = {
    environment = var.environment
    project     = "retail-platform"
    managed-by  = "terraform"
  }
}

# ── Dataset: retail_raw ───────────────────────────────────

resource "google_bigquery_dataset" "raw" {
  dataset_id                 = var.dataset_raw
  friendly_name              = "Retail Raw"
  description                = "External tables pointing directly at Google Sheets tabs. Managed by Terraform."
  location                   = var.bq_location
  labels                     = local.bq_labels
  delete_contents_on_destroy = false
  depends_on                 = [google_project_service.bigquery]
}

# ── Dataset: retail_staging ───────────────────────────────

resource "google_bigquery_dataset" "staging" {
  dataset_id                 = var.dataset_staging
  friendly_name              = "Retail Staging"
  description                = "dbt staging models: cleaned and typed data."
  location                   = var.bq_location
  labels                     = local.bq_labels
  delete_contents_on_destroy = false
  depends_on                 = [google_project_service.bigquery]
}

# ── Dataset: retail_marts ─────────────────────────────────

resource "google_bigquery_dataset" "marts" {
  dataset_id                 = var.dataset_marts
  friendly_name              = "Retail Marts"
  description                = "dbt mart models: business-ready aggregations for Looker Studio."
  location                   = var.bq_location
  labels                     = local.bq_labels
  delete_contents_on_destroy = false
  depends_on                 = [google_project_service.bigquery]
}

# External tables removed — ingestion now handled by etl/extract_load.py
# which loads native BigQuery tables (no Drive credentials needed).
