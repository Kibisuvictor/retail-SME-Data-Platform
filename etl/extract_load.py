"""
extract_load.py
───────────────
Reads all 5 Google Sheets tabs via the Sheets API (service account auth)
and loads them into native BigQuery tables in retail_raw.

This replaces the external-tables approach, which required BigQuery to
hold Drive credentials. Here, only this script touches the Sheet, using
a plain service account key — no OAuth flows, no Drive scopes on BigQuery.

Auth setup (one-time):
  1. terraform output -raw dbt_sa_key_base64 | base64 -d > credentials/dbt-sa-key.json
  2. Share the Google Sheet with the service account email (Viewer)

Run:
  export GCP_PROJECT_ID=retail-data-platform-498819
  export GOOGLE_SHEET_ID=your_sheet_id
  export GOOGLE_APPLICATION_CREDENTIALS=../credentials/dbt-sa-key.json
  python extract_load.py
"""

import os
import sys
import logging
from datetime import datetime, timezone

import gspread
import pandas as pd
from google.cloud import bigquery
from google.oauth2.service_account import Credentials

# ─────────────────────────────────────────
# Config
# ─────────────────────────────────────────

PROJECT_ID = os.environ["GCP_PROJECT_ID"]
SHEET_ID = os.environ["GOOGLE_SHEET_ID"]
CREDS_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "../credentials/dbt-sa-key.json")
DATASET = os.environ.get("BQ_DATASET_RAW", "retail_raw")

SCOPES = ["https://www.googleapis.com/auth/spreadsheets.readonly"]

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ─────────────────────────────────────────
# Sheet tab → BigQuery table, plus explicit header rename maps.
# Keys = EXACT Google Form headers as they appear in the Sheet.
# Values = canonical column names the dbt staging models expect.
# ─────────────────────────────────────────

SHEETS = {
    "Sales": {
        "table": "sales_raw",
        "renames": {
            "Timestamp":              "Timestamp",
            "Date":                   "Date",
            "Salesperson Name":       "Salesperson_Name",
            "Product":                "Product",
            "Units Sold":             "Units_Sold",
            "Unit Price (KES)":       "Unit_Price_KES",
            "Discount Amount (KES)":  "Discount_Amount_KES",
            "Payment Method":         "Payment_Method",
            "Customer Phone Number":  "Customer_Phone_Number",
            "Customer Type":          "Customer_Type",
            "Notes":                  "Notes",
        },
    },
    "Expenses": {
        "table": "expenses_raw",
        "renames": {
            "Timestamp":         "Timestamp",
            "Date of Expense":   "Date_of_Expense",
            "Expense Category":  "Expense_Category",
            "Amount (KES)":      "Amount_KES",
            "Description":       "Description",
            "Paid Via":          "Paid_Via",
            "Recorded By":       "Recorded_By",
        },
    },
    "Inventory": {
        "table": "inventory_purchases_raw",
        "renames": {
            "Timestamp":                   "Timestamp",
            "Date of Purchase":            "Date_of_Purchase",
            "Product Purchased":           "Product_Purchased",
            "Units Purchased":             "Units_Purchased",
            "Unit Cost (KES)":             "Unit_Cost_KES",
            "Supplier Name":               "Supplier_Name",
            "Payment Method":              "Payment_Method",
            "Notes/Comments (Optional)":   "Notes_Comments",
        },
    },
    "Returns": {
        "table": "returns_raw",
        "renames": {
            "Timestamp":                                                "Timestamp",
            "Date of Return":                                           "Date_of_Return",
            "Salesperson Name":                                         "Salesperson_Name",
            "Product Returned (Select Item)":                           "Product_Returned",
            "Units Returned (Must be greater than 0)":                  "Units_Returned",
            "Original Unit Price (KES) - What was the item sold for?":  "Original_Unit_Price_KES",
            "Reason for Return":                                        "Reason_for_Return",
            "Requested Refund Method":                                  "Requested_Refund_Method",
            "Customer Phone Number (Optional)":                         "Customer_Phone_Number",
            "Notes and Further Explanation (Optional)":                 "Notes",
        },
    },
    "Products": {
        "table": "products_raw",
        "renames": {
            "Timestamp":                                                 "Timestamp",
            "Product Name (Must be exact for identification purposes)":  "Product_Name",
            "Category":                                                  "Category",
            "Unit of Measure (UoM)":                                     "Unit_of_Measure",
            "Current Selling Price (KES)":                               "Current_Selling_Price",
            "Reorder Level (units) - Default is 5":                      "Reorder_Level",
            "Is this product currently active?":                         "Is_Active",
        },
    },
}


def fetch_tab(client: gspread.Client, tab_name: str) -> pd.DataFrame:
    ws = client.open_by_key(SHEET_ID).worksheet(tab_name)
    records = ws.get_all_records(default_blank=None)
    df = pd.DataFrame(records)
    log.info(f"  Fetched {len(df)} rows from tab '{tab_name}'")
    return df


def prepare(df: pd.DataFrame, renames: dict, tab_name: str) -> pd.DataFrame:
    # Strip whitespace from headers before matching
    df.columns = [str(c).strip() for c in df.columns]

    # Warn about headers we don't recognise (won't be loaded)
    unknown = [c for c in df.columns if c not in renames]
    if unknown:
        log.warning(f"  '{tab_name}': ignoring unrecognised columns: {unknown}")

    # Warn about expected headers missing from the Sheet
    missing = [c for c in renames if c not in df.columns]
    if missing:
        log.warning(f"  '{tab_name}': expected headers not found: {missing}")

    df = df[[c for c in df.columns if c in renames]].rename(columns=renames)

    # Add any missing canonical columns as empty so the table schema is stable
    for canonical in renames.values():
        if canonical not in df.columns:
            df[canonical] = None

    # Everything as string; dbt staging does the casting
    df = df.astype("string")
    df = df.replace({"": pd.NA, "None": pd.NA, "nan": pd.NA})

    # Audit columns
    df["_loaded_at"] = datetime.now(timezone.utc).isoformat()
    df["_source"] = "google_sheets_python_etl"
    return df


def load(bq: bigquery.Client, df: pd.DataFrame, table: str) -> None:
    table_id = f"{PROJECT_ID}.{DATASET}.{table}"
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,  # full replace = idempotent
        schema=[bigquery.SchemaField(col, "STRING") for col in df.columns],
    )
    job = bq.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    log.info(f"  Loaded {len(df)} rows → {table_id}")


def run() -> None:
    log.info("=" * 60)
    log.info("Retail ETL — Google Sheets → BigQuery (native tables)")
    log.info(f"Project: {PROJECT_ID} | Dataset: {DATASET}")
    log.info("=" * 60)

    creds = Credentials.from_service_account_file(CREDS_PATH, scopes=SCOPES)
    gs_client = gspread.authorize(creds)
    bq_client = bigquery.Client(project=PROJECT_ID)  # uses ADC or the same key via env var

    errors = []
    for tab_name, cfg in SHEETS.items():
        log.info(f"Processing: '{tab_name}' → {DATASET}.{cfg['table']}")
        try:
            df = fetch_tab(gs_client, tab_name)
            if df.empty:
                log.warning(f"  Tab '{tab_name}' is empty — loading empty table with schema only")
            df = prepare(df, cfg["renames"], tab_name)
            load(bq_client, df, cfg["table"])
        except gspread.exceptions.WorksheetNotFound:
            log.error(f"  Tab '{tab_name}' not found in the Sheet — check tab names")
            errors.append(tab_name)
        except Exception as e:
            log.error(f"  FAILED on '{tab_name}': {e}")
            errors.append(tab_name)

    log.info("=" * 60)
    if errors:
        log.error(f"ETL finished with errors in: {errors}")
        sys.exit(1)
    log.info("ETL complete. Next: dbt run")


if __name__ == "__main__":
    run()
