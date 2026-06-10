# ─────────────────────────────────────────────────────────
# iam.tf
# Service accounts and IAM bindings.
#
# Two identities:
#   1. dbt_runner       — runs dbt transformations (you, locally or in CI)
#   2. dbt_sa           — service account for Cloud Scheduler + GitHub Actions
#
# Principle of least privilege throughout:
#   - raw dataset      → read only (external tables, no writes needed)
#   - staging dataset  → read + write (dbt creates tables here)
#   - marts dataset    → read + write (dbt creates tables here)
#   - Looker Studio viewers → read only on marts
# ─────────────────────────────────────────────────────────

# ── Service Account: dbt runner ───────────────────────────
# Used by Cloud Scheduler and optionally GitHub Actions CI.
# For local development you use your own gcloud credentials instead.

resource "google_service_account" "dbt_sa" {
  account_id   = "retail-dbt-runner"
  display_name = "Retail dbt Runner"
  description  = "Service account for running dbt transformations via Cloud Scheduler and CI/CD."

  depends_on = [google_project_service.iam]
}

# ── IAM: dbt runner (your personal email — local dev) ─────

# Read raw external tables
resource "google_bigquery_dataset_iam_member" "dbt_runner_raw_viewer" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "user:${var.dbt_runner_email}"
}

# Read + write staging (dbt builds models here)
resource "google_bigquery_dataset_iam_member" "dbt_runner_staging_editor" {
  dataset_id = google_bigquery_dataset.staging.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "user:${var.dbt_runner_email}"
}

# Read + write marts (dbt builds models here)
resource "google_bigquery_dataset_iam_member" "dbt_runner_marts_editor" {
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "user:${var.dbt_runner_email}"
}

# Run BigQuery jobs (required to execute queries)
resource "google_project_iam_member" "dbt_runner_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "user:${var.dbt_runner_email}"
}

# ── IAM: dbt service account (Cloud Scheduler / CI) ───────

resource "google_bigquery_dataset_iam_member" "dbt_sa_raw_viewer" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_sa_staging_editor" {
  dataset_id = google_bigquery_dataset.staging.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_sa.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_sa_marts_editor" {
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_sa.email}"
}

resource "google_project_iam_member" "dbt_sa_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt_sa.email}"
}

# ── IAM: Looker Studio dashboard viewers ──────────────────
# Business owner and other viewers get read-only access to marts.
# They can connect Looker Studio to BigQuery but cannot modify data.

resource "google_bigquery_dataset_iam_member" "dashboard_viewers_marts" {
  for_each = toset(var.dashboard_viewer_emails)

  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "user:${each.value}"
}

resource "google_project_iam_member" "dashboard_viewers_job_user" {
  for_each = toset(var.dashboard_viewer_emails)

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "user:${each.value}"
}

# ── Service Account Key (for GitHub Actions CI) ───────────
# Creates a JSON key for the dbt service account.
# Used in GitHub Actions secrets — NOT committed to the repo.

resource "google_service_account_key" "dbt_sa_key" {
  service_account_id = google_service_account.dbt_sa.name
  key_algorithm      = "KEY_ALG_RSA_2048"
}
