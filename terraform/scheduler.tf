# ─────────────────────────────────────────────────────────
# scheduler.tf
# Cloud Scheduler job that triggers a daily dbt run.
#
# Strategy: Scheduler → Pub/Sub topic → triggers a workflow.
# For simplicity at this scale we use a Pub/Sub HTTP target
# that can be consumed by GitHub Actions (workflow_dispatch)
# or a Cloud Run job if you containerise dbt later.
#
# The simplest free-tier approach:
#   Cloud Scheduler publishes to a Pub/Sub topic daily.
#   A Cloud Run Job (or GitHub Actions) subscribes and runs dbt.
# ─────────────────────────────────────────────────────────

# ── Pub/Sub topic ─────────────────────────────────────────
# Scheduler writes here; your dbt runner listens here.

resource "google_pubsub_topic" "dbt_trigger" {
  name   = "retail-dbt-trigger"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  depends_on = [google_project_service.bigquery]
}

# ── Cloud Scheduler job ───────────────────────────────────
# Runs at the configured schedule (default: 03:00 UTC = 06:00 EAT).
# Publishes a message to the Pub/Sub topic.

resource "google_cloud_scheduler_job" "dbt_daily" {
  name        = "retail-dbt-daily-run"
  description = "Triggers daily dbt transformations for the retail data platform."
  schedule    = var.dbt_schedule
  time_zone   = "Africa/Nairobi"
  region      = var.region

  pubsub_target {
    topic_name = google_pubsub_topic.dbt_trigger.id

    data = base64encode(jsonencode({
      action      = "dbt_run"
      environment = var.environment
      triggered_by = "cloud_scheduler"
      timestamp   = "auto"
    }))
  }

  retry_config {
    retry_count          = 3
    min_backoff_duration = "5s"
    max_backoff_duration = "3600s"
    max_doublings        = 5
  }

  depends_on = [
    google_project_service.cloud_scheduler,
    google_pubsub_topic.dbt_trigger,
  ]
}

# ── Scheduler service account ─────────────────────────────
# Dedicated SA for Cloud Scheduler to publish to Pub/Sub.

resource "google_service_account" "scheduler_sa" {
  account_id   = "retail-scheduler"
  display_name = "Retail Cloud Scheduler"
  description  = "Service account used by Cloud Scheduler to publish dbt trigger messages."
}

resource "google_pubsub_topic_iam_member" "scheduler_publisher" {
  topic  = google_pubsub_topic.dbt_trigger.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.scheduler_sa.email}"
}
