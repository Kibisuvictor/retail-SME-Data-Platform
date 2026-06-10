#!/bin/bash
# ─────────────────────────────────────────────────────────
# schedule_cron.sh
# Sets up Cloud Scheduler to trigger dbt runs daily at 6 AM EAT.
#
# Uses a Cloud Run Job to execute dbt in a container.
# Alternative (simpler): run from your laptop via cron if always on.
#
# Usage:
#   bash scripts/schedule_cron.sh
# ─────────────────────────────────────────────────────────

set -euo pipefail

if [ -f .env ]; then export $(grep -v '^#' .env | xargs); fi

PROJECT="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID in .env}"
REGION="europe-west1"         # closest GCP region to Kenya
JOB_NAME="retail-dbt-daily"
# 6 AM EAT = 3 AM UTC
SCHEDULE="0 3 * * *"
TIMEZONE="Africa/Nairobi"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Setting up Cloud Scheduler job: $JOB_NAME"
log "Schedule: $SCHEDULE ($TIMEZONE)"

gcloud config set project "$PROJECT"
gcloud services enable cloudscheduler.googleapis.com --quiet

# ── Option A: Simple HTTP trigger ─────────────────────────
# If you run dbt from Cloud Shell, the simplest approach
# is a scheduled script. Cloud Scheduler can also trigger
# a Cloud Run Job or a Pub/Sub message.

# Create or update the scheduler job
gcloud scheduler jobs create http "$JOB_NAME" \
    --location="$REGION" \
    --schedule="$SCHEDULE" \
    --time-zone="$TIMEZONE" \
    --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/triggers/retail-dbt-trigger:run" \
    --message-body='{}' \
    --oauth-service-account-email="${PROJECT}@appspot.gserviceaccount.com" \
    --description="Daily dbt run for retail data platform" \
    2>/dev/null || \
gcloud scheduler jobs update http "$JOB_NAME" \
    --location="$REGION" \
    --schedule="$SCHEDULE" \
    --time-zone="$TIMEZONE"

log "Cloud Scheduler job created ✓"
log ""
log "Alternative (simplest): Run dbt from your laptop on a schedule."
log "If you have a machine that's always on, add this to crontab:"
log ""
log "  0 6 * * * cd /path/to/retail_gcp/dbt_retail && dbt run --profiles-dir . >> ~/retail_dbt.log 2>&1"
log ""
log "For most small businesses, running dbt manually or"
log "from Cloud Shell once a day is perfectly sufficient."
