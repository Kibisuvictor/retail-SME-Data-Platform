# Retail SME Data Platform — GCP Edition

An end-to-end, zero-cost data platform for a small Kenyan household-goods retailer.
Replaces manual Excel record-keeping with automated data collection, a governed
BigQuery warehouse, dbt transformations, and mobile-friendly dashboards.

**Stack:** Google Forms → Google Sheets → Python ETL → BigQuery → dbt Core → Looker Studio
**Infrastructure:** Terraform · **Orchestration:** GitHub Actions (daily, 21:00 EAT)
**Monthly cost:** KES 0 (BigQuery free tier)

---

## Architecture

```
Google Forms  (Sales / Expenses / Inventory Purchases / Returns / Products)
      │  auto-appends on every form submission
      ▼
Google Sheets  (one spreadsheet, 5 tabs — raw data entry layer)
      │  Python ETL (Sheets API, service-account auth)
      │  etl/extract_load.py — daily via GitHub Actions
      ▼
BigQuery — retail_raw       (native tables, full refresh, all STRING)
      │  dbt Core
      ▼
BigQuery — retail_staging   (typed, cleaned, validated; 5 models)
      │  dbt Core
      ▼
BigQuery — retail_marts     (8 business-ready models)
      │  native connector
      ▼
Looker Studio  (8 dashboards — shareable link, works on any phone)
```

### Why a Python ETL instead of BigQuery external tables?

The first iteration used BigQuery external tables reading Google Sheets directly.
This requires BigQuery itself to hold Drive-scoped credentials, which proved
fragile (`Permission denied while getting Drive credentials`). The platform was
migrated to a Python ETL that authenticates to the Sheets API with a plain
service-account key and loads native BigQuery tables. Result: simpler auth,
faster queries (native tables), and an explicit, testable ingestion step.

---

## Data Model

| Layer | Dataset | Contents |
|---|---|---|
| Raw | `retail_raw` | 5 tables mirroring the Sheet tabs, all STRING, full-refreshed by ETL |
| Staging | `retail_staging` | `stg_sales`, `stg_expenses`, `stg_inventory_purchases`, `stg_returns`, `stg_products` — typed, deduplicated, validated |
| Marts | `retail_marts` | `daily_sales_summary`, `monthly_profit`, `inventory_position`, `product_performance`, `salesperson_performance`, `unit_performance`, `expense_summary`, `returns_analysis`, `customer_insights` |

Key design decisions:
- **Stock is derived, never stored:** `stock_on_hand = purchases − sales + returns`
- **Returns are first-class:** dedicated form capturing reason and refund method, feeding inventory restock and a returns-rate mart
- **Phone numbers are masked** in marts (`07XX****XX`) — full numbers never reach dashboards
- **~60 dbt tests** run on every pipeline execution (uniqueness, accepted values, FK relationships, no future dates, no negative stock)

---

## Repository Structure

```
retail_gcp/
├── .github/workflows/
│   └── daily_pipeline.yml      # Daily 21:00 EAT: ETL → dbt run → dbt test
├── etl/
│   ├── extract_load.py         # Sheets API → BigQuery native tables
│   └── requirements.txt
├── dbt_retail/
│   ├── dbt_project.yml
│   ├── profiles.yml            # oauth locally / ADC in CI
│   ├── models/
│   │   ├── staging/            # 5 staging models + sources + tests
│   │   └── marts/              # 8 mart models + tests
│   ├── tests/                  # custom SQL tests
│   └── seeds/                  # product category reference data
├── terraform/
│   ├── main.tf                 # provider + API enablement
│   ├── bigquery.tf             # 3 datasets
│   ├── iam.tf                  # service accounts + least-privilege bindings
│   ├── variables.tf / outputs.tf
│   └── terraform.tfvars.example
└── docs/
    ├── bigquery_setup.md
    ├── looker_studio_setup.md  # all 8 dashboards, card by card
    ├── data_dictionary.md
    ├── metric_definitions.md
    └── data_governance_policy.md
```

---

## Setup

### Prerequisites
Terraform ≥ 1.5, Python 3.11, gcloud CLI authenticated (`gcloud auth login` and
`gcloud auth application-default login`), a GCP project with billing enabled
(free tier — set a $1 budget alert).

### 1. Provision infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in project ID, sheet ID, emails
terraform init && terraform apply
```

### 2. Set up ETL credentials
```bash
terraform output -raw dbt_sa_key_base64 | base64 -d > ../credentials/dbt-sa-key.json
terraform output dbt_service_account_email
# Share the Google Sheet with that email (Viewer)
```

### 3. Run the pipeline locally
```bash
cd ../etl
pip install -r requirements.txt
export GCP_PROJECT_ID=<project-id>
export GOOGLE_SHEET_ID=<sheet-id>
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/../credentials/dbt-sa-key.json"
python extract_load.py

cd ../dbt_retail
pip install dbt-bigquery==1.11.1
dbt deps --profiles-dir .
dbt seed --profiles-dir .      # first run only
dbt run  --profiles-dir .
dbt test --profiles-dir .
```

### 4. Automate with GitHub Actions
Add three repository secrets: `GOOGLE_CREDENTIALS` (contents of the key JSON),
`GCP_PROJECT_ID`, `GOOGLE_SHEET_ID`. The workflow then runs daily at 21:00 EAT
and on every push to main. Trigger manually any time via the Actions tab.

### 5. Dashboards
Connect Looker Studio to `retail_marts`, build the 8 dashboards per
`docs/looker_studio_setup.md`, set data-source freshness to 1 hour, and share
the report link. On a phone: open the link → "Add to Home screen".

---

## Daily Operations

| Time | What happens |
|---|---|
| All day | Salespeople and owner submit Google Forms (no training needed) |
| 21:00 EAT | GitHub Actions: ETL refreshes `retail_raw`, dbt rebuilds staging + marts, tests run |
| Next morning | Owner opens the dashboard link — fresh numbers, low-stock alerts, daily P&L |

Data entry roles: salespeople use the Sales and Returns forms; the owner uses
Expenses, Inventory Purchases, and Products. The Sheet itself is locked —
forms are the only write path.

---

## Governance

- Least-privilege IAM via Terraform (raw/staging/marts each scoped separately)
- Audit columns (`_loaded_at`, `_source`) on every raw row
- Secrets never committed: `.gitignore` covers credentials, tfvars, and state
- Data dictionary, metric definitions, and governance policy in `docs/`