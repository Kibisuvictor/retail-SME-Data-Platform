# Setup Guide — BigQuery, ETL, and Pipeline

How the platform gets data into BigQuery and how to set it up from scratch.

> **Architecture note:** The first iteration used BigQuery *external tables*
> reading Google Sheets directly. That required BigQuery to hold Drive-scoped
> credentials, which repeatedly failed with
> `Permission denied while getting Drive credentials`. The platform now uses a
> **Python ETL** (`etl/extract_load.py`) that reads the Sheet via the Sheets API
> with a service-account key and loads **native BigQuery tables**. Simpler auth,
> faster queries, explicit ingestion step.

---

## How ingestion works

1. `etl/extract_load.py` authenticates to the Sheets API with the
   `retail-dbt-runner` service account key.
2. It reads all 5 tabs (Sales, Expenses, Inventory Purchases, Returns, Products).
3. Headers are renamed via explicit maps in the script — e.g.
   `"Unit Price (KES)"` → `Unit_Price_KES`. **If you rename a Form field, update
   the matching rename map in the script.**
4. Each tab is loaded into `retail_raw.<table>` with `WRITE_TRUNCATE`
   (full replace — idempotent, safe to re-run any time).
5. dbt then builds `retail_staging` and `retail_marts`.

---

## One-time setup

### 1. GCP project
Create a project at console.cloud.google.com, enable billing (free tier — set a
$1 budget alert under Billing → Budgets), and note the **Project ID**.

### 2. Google Sheet
One spreadsheet with 5 tabs: `Sales`, `Expenses`, `Inventory Purchases`,
`Returns`, `Products`. Each tab's row 1 holds the Google Form headers (the
Forms create these automatically when linked). Note the **Sheet ID** from the URL.

### 3. Infrastructure (Terraform)
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in real values
terraform init && terraform apply
```
Creates: 3 BigQuery datasets, the `retail-dbt-runner` service account,
least-privilege IAM (dataEditor on all three datasets + jobUser), and a key.

### 4. ETL credentials
```bash
terraform output -raw dbt_sa_key_base64 | base64 -d > ../credentials/dbt-sa-key.json
terraform output dbt_service_account_email
```
**Share the Google Sheet with that service-account email (Viewer).** This is the
only manual permission step — without it the ETL gets a 403 from the Sheets API.

### 5. Run locally
```bash
cd ../etl && pip install -r requirements.txt
export GCP_PROJECT_ID=<project-id>
export GOOGLE_SHEET_ID=<sheet-id>
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/../credentials/dbt-sa-key.json"
python extract_load.py

cd ../dbt_retail
dbt deps --profiles-dir .
dbt seed --profiles-dir .     # first run only
dbt run  --profiles-dir .
dbt test --profiles-dir .
```

### 6. Automate (GitHub Actions)
Add repo secrets `GOOGLE_CREDENTIALS` (full JSON contents of the key file),
`GCP_PROJECT_ID`, `GOOGLE_SHEET_ID`. The workflow
`.github/workflows/daily_pipeline.yml` then runs ETL → dbt run → dbt test
daily at **21:00 EAT** (18:00 UTC), on every push to main, and on demand via
the "Run workflow" button.

---

## Verifying

```bash
# Raw landed?
bq query --use_legacy_sql=false \
  'SELECT COUNT(*) FROM `<project>.retail_raw.sales_raw`'

# Marts built?
bq ls <project>:retail_marts
```

---

## Common changes

| Change | What to update |
|---|---|
| Renamed a Form field | The rename map for that tab in `etl/extract_load.py`; staging model if the canonical name changes |
| New Form field | Add to rename map → add to the staging model → re-run |
| New product / salesperson / category | Form dropdowns only — no code changes (categories also have an `accepted_values` test in `_staging_models.yml` to extend) |
| New expense category | Form dropdown + `accepted_values` list in `_staging_models.yml` |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| ETL: `403` or `PERMISSION_DENIED` on Sheets | Sheet not shared with the service-account email |
| ETL warning: `expected headers not found` | A Form header was renamed — update the rename map |
| dbt: `Unrecognized name: <column>` | Staging model references a column the ETL doesn't produce — align with the rename maps |
| dbt relationship test fails on `product_key` | Product name in a Sales/Returns/Purchase entry doesn't exactly match the Products tab — fix the dropdown options |
| GitHub Actions auth error | `GOOGLE_CREDENTIALS` secret missing or contains base64 instead of raw JSON |
