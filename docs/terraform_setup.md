# Terraform Setup Guide

> **Updated architecture:** Terraform no longer manages BigQuery external tables —
> ingestion is handled by `etl/extract_load.py` (see `bigquery_setup.md`).
> Terraform now manages: GCP APIs, the 3 BigQuery datasets, service accounts,
> IAM bindings, and (optionally) Cloud Scheduler — though scheduling has moved
> to GitHub Actions, so `scheduler.tf` can be deleted if you prefer a tidy setup.

Complete guide to provisioning the retail data platform infrastructure with Terraform.  
Run time: **~5 minutes** after prerequisites are met.

---

## What Terraform manages

| Resource | File | Description |
|----------|------|-------------|
| GCP APIs | `main.tf` | BigQuery, Sheets, Drive, Scheduler, IAM |
| BigQuery datasets | `bigquery.tf` | `retail_raw`, `retail_staging`, `retail_marts` |
| Service accounts | `iam.tf` | `retail-dbt-runner`, `retail-scheduler` |
| IAM bindings | `iam.tf` | Least-privilege access for all identities |
| Cloud Scheduler | `scheduler.tf` | Daily dbt trigger at 06:00 EAT |
| Pub/Sub topic | `scheduler.tf` | Messaging channel for scheduler → dbt |

## What Terraform does NOT manage

| Resource | Reason |
|----------|--------|
| Google Forms | No Terraform provider |
| Google Sheets content | Data, not infrastructure |
| dbt models | dbt manages its own objects |
| Looker Studio dashboards | No stable provider |

---

## Prerequisites

### 1. Install Terraform
```bash
# macOS (Homebrew)
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

# Linux / WSL
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify
terraform version   # should be >= 1.5.0
```

### 2. Install and authenticate gcloud CLI
```bash
# Install: https://cloud.google.com/sdk/docs/install

# Authenticate (uses your Google account — no service account needed for local apply)
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### 3. Create your Google Sheet
Before running Terraform, create the Google Sheet with four tabs:
- `Sales`
- `Expenses`
- `Inventory Purchases`
- `Products`

Add column headers to each tab (see `docs/bigquery_setup.md` → Step 6).  
Copy the Sheet ID from the URL.

---

## First-Time Setup

### Step 1 — Configure variables
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars    # fill in all values
```

The minimum you need to fill in:
```hcl
project_id             = "your-project-id"
google_sheet_id        = "your-sheet-id"
dbt_runner_email       = "you@gmail.com"
dashboard_viewer_emails = ["owner@gmail.com"]
```

### Step 2 — Initialise Terraform
```bash
terraform init
```

This downloads the Google provider plugin (~50MB). You only run this once, or after changing providers.

### Step 3 — Preview what will be created
```bash
terraform plan \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="google_sheet_id=YOUR_SHEET_ID" \
  -var="dbt_runner_email=you@gmail.com"
```

Or if you have `terraform.tfvars` filled in, just:
```bash
terraform plan
```

You should see: **16 to add, 0 to change, 0 to destroy**

Review the plan carefully before applying.

### Step 4 — Apply
```bash
terraform apply
```

Type `yes` when prompted.

Terraform will:
1. Enable 6 GCP APIs
2. Create 3 BigQuery datasets
3. Create 4 external tables over your Sheets
4. Create 2 service accounts
5. Set up all IAM bindings
6. Create Cloud Scheduler job + Pub/Sub topic

### Step 5 — Read the outputs
After apply completes, Terraform prints outputs including:

```
dbt_service_account_email = "retail-dbt-runner@YOUR-PROJECT.iam.gserviceaccount.com"
next_steps = ...
external_tables = {
  sales_raw = "YOUR-PROJECT.retail_raw.sales_raw"
  ...
}
```

### Step 6 — Share Google Sheet with service account
This is the one manual step:
1. Open your Google Sheet
2. Click **Share**
3. Add the `dbt_service_account_email` from the output above
4. Set as **Viewer**
5. Click **Send**

Without this step, BigQuery cannot read the Sheet data.

### Step 7 — Get the CI service account key
```bash
terraform output -raw dbt_sa_key_base64
```

Copy this value. You'll add it as a GitHub Actions secret in the next step.

---

## Setting Up GitHub Actions

Add these secrets to your GitHub repo (Settings → Secrets → Actions):

| Secret Name | Value |
|-------------|-------|
| `GOOGLE_CREDENTIALS` | Output of `terraform output -raw dbt_sa_key_base64` |
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GOOGLE_SHEET_ID` | Your Google Sheet ID |
| `DBT_RUNNER_EMAIL` | Your email |
| `DASHBOARD_VIEWER_EMAILS` | JSON array: `["owner@gmail.com"]` |

After adding secrets, the CI/CD pipeline will:
- On every PR → run `terraform plan` + `dbt compile` (no writes)
- On every push to `main` → run `terraform apply` + `dbt run` + `dbt test`
- Every day at 06:00 EAT → run `dbt run` + `dbt test`

---

## Day-to-Day Terraform Commands

```bash
# See what's currently deployed
terraform show

# See all output values
terraform output

# Check if anything has drifted from state
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy everything (careful!)
terraform destroy

# Format all .tf files
terraform fmt -recursive

# Validate configuration
terraform validate
```

---

## Making Infrastructure Changes

### Example: Add a new dashboard viewer
1. Edit `terraform.tfvars`:
   ```hcl
   dashboard_viewer_emails = ["owner@gmail.com", "newviewer@gmail.com"]
   ```
2. Run `terraform plan` to preview
3. Run `terraform apply` — adds the IAM binding, nothing else changes

### Example: Change the dbt schedule
1. Edit `terraform.tfvars`:
   ```hcl
   dbt_schedule = "0 4 * * *"   # 07:00 EAT instead of 06:00
   ```
2. `terraform apply` — updates Cloud Scheduler, nothing else changes

### Example: Add a new BigQuery dataset
1. Add to `bigquery.tf`:
   ```hcl
   resource "google_bigquery_dataset" "reporting" {
     dataset_id = "retail_reporting"
     location   = var.bq_location
     labels     = local.bq_labels
   }
   ```
2. `terraform plan` → `terraform apply`

---

## Remote State (Recommended for Teams)

By default Terraform stores state locally in `terraform.tfstate`.  
For safety, store it in GCS instead:

### Create a state bucket (one-time, manual)
```bash
gsutil mb -l EU gs://${GCP_PROJECT_ID}-tfstate
gsutil versioning set on gs://${GCP_PROJECT_ID}-tfstate
```

### Enable backend in main.tf
Uncomment the `backend "gcs"` block in `main.tf`:
```hcl
backend "gcs" {
  bucket = "YOUR-PROJECT-tfstate"
  prefix = "retail-platform/state"
}
```

Then run `terraform init` again to migrate local state to GCS.

With remote state:
- State file is never on your laptop
- Multiple people can run Terraform safely
- State is versioned and recoverable

---

## Troubleshooting

**Error: "API has not been used in project"**  
→ Run `terraform apply` again — API enablement sometimes takes 30–60 seconds to propagate.

**Error: "Permission denied on Google Sheets"**  
→ You haven't shared the Sheet with the service account yet (Step 6 above).

**Error: "googleapi: Error 409: Already Exists"**  
→ The resource was created outside Terraform. Import it:
```bash
terraform import google_bigquery_dataset.raw YOUR_PROJECT:retail_raw
```

**Error: "terraform.tfvars not found"**  
→ Copy the example file: `cp terraform.tfvars.example terraform.tfvars`

**External table shows no data**  
→ Check that the Sheet tab name exactly matches what's in `bigquery.tf` (e.g. "Inventory Purchases" with a space).  
→ Check the Sheet has headers in row 1 and data in row 2+.
