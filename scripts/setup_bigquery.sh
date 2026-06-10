#!/bin/bash
# ─────────────────────────────────────────────────────────
# setup_bigquery.sh
# One-command setup: creates BigQuery datasets and external
# tables that point directly at your Google Sheets tabs.
#
# Run once after cloning the repo:
#   bash scripts/setup_bigquery.sh
#
# Requirements:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - .env file configured with GCP_PROJECT_ID and GOOGLE_SHEET_ID
# ─────────────────────────────────────────────────────────

set -euo pipefail

# ── Load env vars ─────────────────────────────────────────
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "ERROR: .env file not found. Copy .env.example to .env and fill in your values."
    exit 1
fi

PROJECT="${GCP_PROJECT_ID:?GCP_PROJECT_ID not set in .env}"
LOCATION="${BQ_LOCATION:-EU}"
SHEET_ID="${GOOGLE_SHEET_ID:?GOOGLE_SHEET_ID not set in .env}"

DATASET_RAW="${BQ_DATASET_RAW:-retail_raw}"
DATASET_STAGING="${BQ_DATASET_STAGING:-retail_staging}"
DATASET_MARTS="${BQ_DATASET_MARTS:-retail_marts}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "═══════════════════════════════════════════"
log "Retail GCP Platform — BigQuery Setup"
log "Project  : $PROJECT"
log "Location : $LOCATION"
log "Sheet ID : $SHEET_ID"
log "═══════════════════════════════════════════"

# ── Set active project ────────────────────────────────────
gcloud config set project "$PROJECT"

# ── Enable required APIs ──────────────────────────────────
log "Enabling required Google APIs..."
gcloud services enable bigquery.googleapis.com --quiet
gcloud services enable sheets.googleapis.com --quiet
gcloud services enable drive.googleapis.com --quiet
gcloud services enable cloudscheduler.googleapis.com --quiet
log "APIs enabled ✓"

# ── Create BigQuery datasets ──────────────────────────────
log "Creating BigQuery datasets..."

for DATASET in "$DATASET_RAW" "$DATASET_STAGING" "$DATASET_MARTS"; do
    if bq ls --project_id="$PROJECT" "$DATASET" > /dev/null 2>&1; then
        log "  Dataset '$DATASET' already exists — skipping"
    else
        bq mk \
            --project_id="$PROJECT" \
            --location="$LOCATION" \
            --dataset \
            --description="Retail platform — $DATASET layer" \
            "$DATASET"
        log "  Created dataset: $DATASET ✓"
    fi
done

# ── Create External Tables (Sheets → BigQuery) ────────────
# Each external table reads directly from a Google Sheet tab.
# No data is copied — BigQuery reads the Sheet live on every query.
# This means dashboards always reflect the latest form submissions.

log "Creating external tables over Google Sheets..."

# Helper function to create one external table
create_external_table() {
    local TABLE_NAME="$1"
    local SHEET_TAB_NAME="$2"
    local SCHEMA_FILE="$3"

    FULL_TABLE="${PROJECT}:${DATASET_RAW}.${TABLE_NAME}"
    SHEET_URL="https://docs.google.com/spreadsheets/d/${SHEET_ID}"

    # Write external table definition JSON
    cat > /tmp/ext_table_def.json << EOF
{
  "sourceFormat": "GOOGLE_SHEETS",
  "sourceUris": ["${SHEET_URL}"],
  "googleSheetsOptions": {
    "sheetRange": "${SHEET_TAB_NAME}",
    "skipLeadingRows": 1
  },
  "autodetect": false,
  "schema": {
    "fields": $(cat "$SCHEMA_FILE")
  }
}
EOF

    # Drop and recreate (idempotent)
    bq rm --force --table "${PROJECT}:${DATASET_RAW}.${TABLE_NAME}" 2>/dev/null || true

    bq mk \
        --project_id="$PROJECT" \
        --table \
        --external_table_definition=/tmp/ext_table_def.json \
        "${DATASET_RAW}.${TABLE_NAME}"

    log "  External table created: ${DATASET_RAW}.${TABLE_NAME} → Sheet tab '${SHEET_TAB_NAME}' ✓"
}

# Write schema files
# All columns are STRING in external tables — dbt does type casting in staging

cat > /tmp/schema_sales.json << 'EOF'
[
  {"name": "Timestamp",           "type": "STRING", "mode": "NULLABLE"},
  {"name": "Date",                "type": "STRING", "mode": "NULLABLE"},
  {"name": "Salesperson_Name",    "type": "STRING", "mode": "NULLABLE"},
  {"name": "Product",             "type": "STRING", "mode": "NULLABLE"},
  {"name": "Units_Sold",          "type": "STRING", "mode": "NULLABLE"},
  {"name": "Unit_Price_KES",      "type": "STRING", "mode": "NULLABLE"},
  {"name": "Discount_Amount_KES", "type": "STRING", "mode": "NULLABLE"},
  {"name": "Payment_Method",      "type": "STRING", "mode": "NULLABLE"},
  {"name": "Return",              "type": "STRING", "mode": "NULLABLE"},
  {"name": "Customer_Phone_Number","type": "STRING", "mode": "NULLABLE"},
  {"name": "Notes",               "type": "STRING", "mode": "NULLABLE"}
]
EOF

cat > /tmp/schema_expenses.json << 'EOF'
[
  {"name": "Timestamp",        "type": "STRING", "mode": "NULLABLE"},
  {"name": "Date",             "type": "STRING", "mode": "NULLABLE"},
  {"name": "Expense_Category", "type": "STRING", "mode": "NULLABLE"},
  {"name": "Amount_KES",       "type": "STRING", "mode": "NULLABLE"},
  {"name": "Description",      "type": "STRING", "mode": "NULLABLE"},
  {"name": "Paid_Via",         "type": "STRING", "mode": "NULLABLE"},
  {"name": "Recorded_By",      "type": "STRING", "mode": "NULLABLE"}
]
EOF

cat > /tmp/schema_inventory.json << 'EOF'
[
  {"name": "Timestamp",        "type": "STRING", "mode": "NULLABLE"},
  {"name": "Date",             "type": "STRING", "mode": "NULLABLE"},
  {"name": "Product",          "type": "STRING", "mode": "NULLABLE"},
  {"name": "Units_Purchased",  "type": "STRING", "mode": "NULLABLE"},
  {"name": "Unit_Cost_KES",    "type": "STRING", "mode": "NULLABLE"},
  {"name": "Supplier_Name",    "type": "STRING", "mode": "NULLABLE"},
  {"name": "Payment_Method",   "type": "STRING", "mode": "NULLABLE"},
  {"name": "Notes",            "type": "STRING", "mode": "NULLABLE"}
]
EOF

cat > /tmp/schema_products.json << 'EOF'
[
  {"name": "Timestamp",              "type": "STRING", "mode": "NULLABLE"},
  {"name": "Product_Name",           "type": "STRING", "mode": "NULLABLE"},
  {"name": "Category",               "type": "STRING", "mode": "NULLABLE"},
  {"name": "Unit_of_Measure",        "type": "STRING", "mode": "NULLABLE"},
  {"name": "Current_Selling_Price",  "type": "STRING", "mode": "NULLABLE"},
  {"name": "Reorder_Level_Units",    "type": "STRING", "mode": "NULLABLE"},
  {"name": "Active",                 "type": "STRING", "mode": "NULLABLE"}
]
EOF

# Create the four external tables
create_external_table "sales_raw"                 "Sales"                /tmp/schema_sales.json
create_external_table "expenses_raw"              "Expenses"             /tmp/schema_expenses.json
create_external_table "inventory_purchases_raw"   "Inventory Purchases"  /tmp/schema_inventory.json
create_external_table "products_raw"              "Products"             /tmp/schema_products.json

# ── Grant BigQuery access to Sheets ──────────────────────
# The BigQuery service account needs read access to the Sheet.
# Get the SA email and print instructions.
BQ_SA=$(bq show --format=prettyjson --project_id="$PROJECT" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); \
    print(d.get('access',[{}])[0].get('userByEmail',''))" 2>/dev/null || echo "")

log "═══════════════════════════════════════════"
log "Setup complete!"
log ""
log "IMPORTANT — Manual step required:"
log "Share your Google Sheet with BigQuery's service account:"
log ""
log "  1. Open your Google Sheet"
log "  2. Click Share"
log "  3. Add this email as Viewer:"
log "     ${PROJECT}@appspot.gserviceaccount.com"
log "     (or find the exact SA email in IAM console)"
log ""
log "Next steps:"
log "  cd dbt_retail"
log "  pip install dbt-bigquery"
log "  dbt deps"
log "  dbt run"
log "  dbt test"
log "═══════════════════════════════════════════"
