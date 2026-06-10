#!/bin/bash
# ─────────────────────────────────────────────────────────
# run_pipeline.sh
# Runs dbt transformations and tests.
# No ETL needed — BigQuery reads Sheets live via external tables.
#
# Usage:
#   bash scripts/run_pipeline.sh              # full run
#   bash scripts/run_pipeline.sh --test-only  # tests only
#   bash scripts/run_pipeline.sh --full       # includes dbt seed
# ─────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DBT_DIR="$PROJECT_DIR/dbt_retail"
MODE="normal"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S EAT')

for arg in "$@"; do
    case $arg in
        --test-only) MODE="test_only" ;;
        --full)      MODE="full" ;;
    esac
done

log() { echo "[$TIMESTAMP] $1"; }
fail() { log "FAILED: $1"; exit 1; }

# Load env
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

log "═══════════════════════════════════════════"
log "Retail GCP Platform — Pipeline Run"
log "Mode: $MODE | Project: ${GCP_PROJECT_ID:-not set}"
log "═══════════════════════════════════════════"

cd "$DBT_DIR"

# ── Seed reference data (first run or --full only) ────────
if [ "$MODE" = "full" ]; then
    log "Step 1/3: Loading seed data..."
    dbt seed --profiles-dir . \
        || fail "dbt seed failed"
    log "Step 1/3: Seed complete ✓"
else
    log "Step 1/3: Skipped (use --full to load seeds)"
fi

# ── dbt run ───────────────────────────────────────────────
if [ "$MODE" != "test_only" ]; then
    log "Step 2/3: Running dbt transformations..."
    dbt run --profiles-dir . \
        || fail "dbt run failed — check model SQL"
    log "Step 2/3: dbt run complete ✓"
fi

# ── dbt test ──────────────────────────────────────────────
log "Step 3/3: Running dbt tests..."
dbt test --profiles-dir . \
    && log "Step 3/3: All tests passed ✓" \
    || log "WARNING: Some tests failed — review output above"

log "═══════════════════════════════════════════"
log "Pipeline complete. Open Looker Studio to see fresh data."
log "═══════════════════════════════════════════"
