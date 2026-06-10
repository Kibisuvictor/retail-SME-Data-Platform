# BigQuery Setup Guide

Complete step-by-step from zero to a working BigQuery + dbt pipeline.  
Estimated time: **30–45 minutes**

---

## Part 1: Google Cloud Project Setup

### Step 1 — Activate your free tier
1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Sign in with your Google account
3. If not already activated, click **Activate** to get the free tier
4. No credit card required for BigQuery free tier

### Step 2 — Create a project
1. Click the project dropdown at the top of the page → **New Project**
2. Project name: `retail-data-platform`
3. Note your **Project ID** (may differ from name, e.g. `retail-data-platform-123456`)
4. Click **Create**

### Step 3 — Enable BigQuery API
1. In the search bar type: `BigQuery API`
2. Click it → **Enable**
3. Also enable: **Google Sheets API** and **Google Drive API**
   (BigQuery needs these to read your Sheets)

---

## Part 2: Google Sheets Setup

### Step 4 — Create your spreadsheet
1. Go to [sheets.google.com](https://sheets.google.com)
2. Create new spreadsheet named: **Retail Data Platform**
3. Copy the Sheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/**COPY_THIS_PART**/edit`
4. Add this to your `.env` file as `GOOGLE_SHEET_ID`

### Step 5 — Create the four sheet tabs
Rename `Sheet1` to `Sales` and add three more tabs:
- `Sales`
- `Expenses`
- `Inventory Purchases`
- `Products`

### Step 6 — Add column headers to each tab

**Sales tab — Row 1 headers (exact spelling matters):**
```
Timestamp | Date | Salesperson Name | Product | Units Sold | Unit Price KES | Discount Amount KES | Payment Method | Return | Customer Phone Number | Notes
```

**Expenses tab — Row 1 headers:**
```
Timestamp | Date | Expense Category | Amount KES | Description | Paid Via | Recorded By
```

**Inventory Purchases tab — Row 1 headers:**
```
Timestamp | Date | Product | Units Purchased | Unit Cost KES | Supplier Name | Payment Method | Notes
```

**Products tab — Row 1 headers:**
```
Timestamp | Product Name | Category | Unit of Measure | Current Selling Price | Reorder Level Units | Active
```

> **Google Forms will write the Timestamp column automatically.**  
> For now, manually add your product list to the Products tab so BigQuery has data to work with.

### Step 7 — Add your products to the Products tab
Add a row for each product. Example:
```
[leave Timestamp blank]  |  Omo Detergent 1kg  |  Cleaning Supplies  |  Piece  |  280  |  10  |  Yes
```

---

## Part 3: BigQuery External Tables

### Step 8 — Share your Sheet with BigQuery

BigQuery needs permission to read your Sheet. Find the BigQuery service account email:

1. Go to BigQuery in console → your project
2. Look for the service account email — it looks like:
   `bq-[numbers]@[project].iam.gserviceaccount.com`
   
   Or run in Cloud Shell:
   ```bash
   gcloud projects get-iam-policy YOUR_PROJECT_ID \
     --flatten="bindings[].members" \
     --filter="bindings.role:roles/bigquery" \
     --format="value(bindings.members)"
   ```

3. Open your Google Sheet → **Share**
4. Paste the service account email → set as **Viewer** → **Send**

### Step 9 — Run the setup script

Open **Cloud Shell** (the terminal icon `>_` at the top right of the GCP console):

```bash
# Clone your repo
git clone https://github.com/YOUR_USERNAME/retail-gcp-platform
cd retail_gcp

# Set up .env
cp .env.example .env
nano .env   # fill in GCP_PROJECT_ID and GOOGLE_SHEET_ID

# Run setup
bash scripts/setup_bigquery.sh
```

This script:
- Creates three BigQuery datasets: `retail_raw`, `retail_staging`, `retail_marts`
- Creates four external tables pointing at your Sheet tabs
- No data is copied — BigQuery reads Sheets live

### Step 10 — Verify external tables in BigQuery console

1. Go to BigQuery → your project
2. Expand `retail_raw` dataset
3. You should see: `sales_raw`, `expenses_raw`, `inventory_purchases_raw`, `products_raw`
4. Click `products_raw` → **Preview** tab
5. You should see your product rows

> If Preview shows an error about permissions, make sure you shared the Sheet with the BigQuery service account (Step 8).

---

## Part 4: dbt Setup

### Step 11 — Install dbt in Cloud Shell

```bash
pip install dbt-bigquery
dbt --version   # should show dbt-bigquery 1.7.x
```

### Step 12 — Authenticate dbt with BigQuery

dbt uses your Google Cloud login — no separate key file needed:

```bash
gcloud auth application-default login
```

Follow the browser link, log in, and come back to Cloud Shell.

### Step 13 — Run dbt

```bash
cd retail_gcp/dbt_retail

# Install dbt packages (dbt_utils)
dbt deps

# First run — also loads seed data
dbt seed --profiles-dir .

# Run all transformations
dbt run --profiles-dir .

# Run all tests
dbt test --profiles-dir .
```

### Step 14 — Verify in BigQuery console

After `dbt run` succeeds:
1. Go to BigQuery console
2. You should now see data in:
   - `retail_staging` — 4 tables (stg_products, stg_sales, stg_expenses, stg_inventory_purchases)
   - `retail_marts` — 7 tables (inventory_position, daily_sales_summary, etc.)

---

## Part 5: Google Forms Setup

### Step 15 — Create the Sales Entry form

1. Go to [forms.google.com](https://forms.google.com) → New Form
2. Title: **Sales Entry**
3. Add fields:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Date | Date | Yes | |
| Salesperson Name | Dropdown | Yes | Add all salesperson names |
| Product | Dropdown | Yes | Add all product names — must match Products tab exactly |
| Units Sold | Short answer | Yes | Number validation, > 0 |
| Unit Price (KES) | Short answer | Yes | Number validation, > 0 |
| Discount Amount (KES) | Short answer | No | Number validation, ≥ 0 |
| Payment Method | Multiple choice | Yes | M-Pesa / Bank |
| Return? | Multiple choice | No | No / Yes |
| Customer Phone Number | Short answer | No | Hint: 07XXXXXXXX |
| Notes | Paragraph | No | |

4. Click Responses tab (green icon) → **Link to Sheets**
5. Choose **Select existing spreadsheet** → **Retail Data Platform**
6. Set sheet tab: **Sales**

Repeat for the other three forms — Expenses, Inventory Purchases, Products — linking each to the correct tab.

### Step 16 — Test the pipeline end to end

1. Submit a test entry via the Sales form
2. Check it appears in the Sales Google Sheet tab
3. Run dbt:
   ```bash
   cd retail_gcp/dbt_retail
   dbt run --profiles-dir .
   ```
4. Check `retail_marts.daily_sales_summary` in BigQuery — your test entry should appear

---

## Part 6: Automated Daily Runs

### Option A — Cloud Shell (simplest, free)

If you have access to a machine or Cloud Shell, add a cron:

```bash
# Edit crontab
crontab -e

# Add this line (6 AM EAT = 3 AM UTC):
0 3 * * * cd /path/to/retail_gcp/dbt_retail && dbt run --profiles-dir . >> ~/retail_dbt.log 2>&1
```

### Option B — GitHub Actions (free, recommended)

The `.github/workflows/ci.yml` in the repo runs dbt on every push.  
To also run daily, add this to the workflow:

```yaml
on:
  schedule:
    - cron: '0 3 * * *'   # 6 AM EAT
  push:
    branches: [main]
```

With GitHub Actions and Workload Identity Federation (keyless auth), you can run dbt daily for free with no server needed.

---

## Troubleshooting

**"Access Denied" on external table:**
→ Share the Google Sheet with the BigQuery service account (Step 8)

**"Table not found" in dbt:**
→ Make sure `GCP_PROJECT_ID` in `.env` matches your actual project ID exactly

**"No data in staging" after dbt run:**
→ Check the Products sheet has data — without products, the FK relationship tests will fail
→ Run `dbt run --select stg_products` first, then `dbt run`

**External table shows wrong columns:**
→ Column headers in the Sheet must exactly match the schema in `setup_bigquery.sh`
→ Re-run `bash scripts/setup_bigquery.sh` after fixing headers
