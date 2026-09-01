# Data Dictionary

All tables across `retail_raw`, `retail_staging`, and `retail_marts` in BigQuery.
Raw column names are the Google Form headers normalised by the ETL
(`etl/extract_load.py`) — the rename maps there are the source of truth.

---

## Dataset: retail_raw

Native tables, fully replaced on every ETL run (WRITE_TRUNCATE). All columns STRING.
Every table also carries audit columns: `_loaded_at` (UTC ISO timestamp) and
`_source` (`google_sheets_python_etl`).

### sales_raw  ← Sheet tab "Sales"

| Column | Original Form header |
|---|---|
| `Timestamp` | Timestamp (auto) |
| `Date` | Date |
| `Salesperson_Name` | Salesperson Name |
| `Product` | Product |
| `Units_Sold` | Units Sold |
| `Unit_Price_KES` | Unit Price (KES) |
| `Discount_Amount_KES` | Discount Amount (KES) |
| `Payment_Method` | Payment Method |
| `Customer_Phone_Number` | Customer Phone Number |
| `Customer_Type` | Customer Type |
| `Notes` | Notes |

### expenses_raw  ← Sheet tab "Expenses"

| Column | Original Form header |
|---|---|
| `Timestamp` | Timestamp (auto) |
| `Date_of_Expense` | Date of Expense |
| `Expense_Category` | Expense Category |
| `Amount_KES` | Amount (KES) |
| `Description` | Description |
| `Paid_Via` | Paid Via |
| `Recorded_By` | Recorded By |

### inventory_purchases_raw  ← Sheet tab "Inventory Purchases"

| Column | Original Form header |
|---|---|
| `Timestamp` | Timestamp (auto) |
| `Date_of_Purchase` | Date of Purchase |
| `Product_Purchased` | Product Purchased |
| `Units_Purchased` | Units Purchased |
| `Unit_Cost_KES` | Unit Cost (KES) |
| `Supplier_Name` | Supplier Name |
| `Payment_Method` | Payment Method |
| `Notes_Comments` | Notes/Comments (Optional) |

### returns_raw  ← Sheet tab "Returns"

| Column | Original Form header |
|---|---|
| `Timestamp` | Timestamp (auto) |
| `Date_of_Return` | Date of Return |
| `Salesperson_Name` | Salesperson Name |
| `Product_Returned` | Product Returned (Select Item) |
| `Units_Returned` | Units Returned (Must be greater than 0) |
| `Original_Unit_Price_KES` | Original Unit Price (KES) - What was the item sold for? |
| `Reason_for_Return` | Reason for Return |
| `Requested_Refund_Method` | Requested Refund Method |
| `Customer_Phone_Number` | Customer Phone Number (Optional) |
| `Notes` | Notes and Further Explanation (Optional) |

### products_raw  ← Sheet tab "Products"

| Column | Original Form header |
|---|---|
| `Timestamp` | Timestamp (auto) |
| `Product_Name` | Product Name (Must be exact for identification purposes) |
| `Category` | Category |
| `Unit_of_Measure` | Unit of Measure (UoM) |
| `Current_Selling_Price` | Current Selling Price (KES) |
| `Reorder_Level` | Reorder Level (units) - Default is 5 |
| `Is_Active` | Is this product currently active? |

---

## Dataset: retail_staging

Typed, cleaned, deduplicated. Rebuilt by dbt on every run.

### stg_products
| Column | Type | Notes |
|---|---|---|
| `product_key` | STRING PK | Slug of product name, e.g. `omo_detergent_1kg` — join key everywhere |
| `product_name` | STRING | |
| `category` | STRING | |
| `unit_of_measure` | STRING | |
| `selling_price` | NUMERIC | Must be > 0 |
| `reorder_level` | INT64 | Defaults to 5 if blank |
| `is_active` | BOOL | Yes/true/1 → TRUE |
| `submitted_at` | TIMESTAMP | Latest submission wins per product (dedup) |

### stg_sales
| Column | Type | Notes |
|---|---|---|
| `sale_id` | STRING PK | MD5(date, salesperson, product, timestamp) |
| `sale_date` | DATE | |
| `salesperson_name` | STRING | Uppercased |
| `product_key` | STRING FK | → stg_products |
| `units_sold` | INT64 | Rows with ≤ 0 dropped |
| `unit_price` | NUMERIC | |
| `discount_amount` | NUMERIC | Defaults 0 |
| `payment_method` | STRING | M-Pesa or Bank |
| `customer_phone` | STRING | NULL unless valid `^(07|01)\d{8}$` |
| `customer_type` | STRING | |
| `gross_amount` | NUMERIC | units × price |
| `net_amount` | NUMERIC | gross − discount |
| `notes`, `submitted_at` | | |

### stg_expenses
`expense_id` (PK), `expense_date`, `expense_category`, `amount` (> 0 enforced),
`description`, `paid_via`, `recorded_by`, `submitted_at`

### stg_inventory_purchases
`purchase_id` (PK), `purchase_date`, `product_key` (FK), `units_purchased`,
`unit_cost`, `total_cost` (units × cost), `supplier_name`, `payment_method`,
`notes`, `submitted_at`

### stg_returns
`return_id` (PK), `return_date`, `salesperson_name`, `product_key` (FK),
`units_returned`, `original_unit_price`, `return_value` (units × price),
`return_reason`, `refund_method`, `customer_phone` (validated/masked downstream),
`notes`, `submitted_at`

---

## Dataset: retail_marts (what Looker Studio queries)

### inventory_position — one row per active product
Stock derived from movements: `stock_on_hand = total_purchased − total_sold + total_returned`.
Includes `inventory_value_at_cost`, `inventory_value_at_retail`,
`stock_status` (In Stock / Low Stock / Out of Stock), `needs_reorder`,
`latest_unit_cost`, `last_purchase_date`.

### daily_sales_summary — one row per day
`transaction_count`, `units_sold`, `gross_revenue`, `total_discounts`,
`net_revenue`, `units_returned`, `returns_value` (from Returns form),
`effective_revenue` (net − returns), `mpesa_revenue`, `bank_revenue`,
`unique_customers_with_phone`, `active_salespeople`, plus date dimensions
(`day_of_week`, `day_of_month`, `week_start`, `month_start`).

### monthly_profit — one row per month
`gross_revenue`, `total_returns`, `net_revenue`, `total_cogs`
(units × latest cost per product), `total_operating_expenses`,
`gross_profit`, `net_profit`, `net_margin_pct`.

### product_performance — one row per (month, product)
Sales volume/revenue, `total_units_returned` and `total_return_value`
(from Returns form), `latest_cost_price`, `estimated_gross_profit`
(net of returns), `gross_margin_pct` — all scoped to that `month`. Always
includes every active product for every month with any activity, plus the
current month (zero-filled if nothing has sold yet). Filter/group on `month`
in Looker Studio to see a single month instead of all-time totals.

### salesperson_performance — one row per (month, salesperson)
Transactions, units, revenue, discounts given, average transaction value,
M-Pesa vs Bank split, `total_returns_processed`, `total_return_value` — all
scoped to that `month`. Only includes months a salesperson actually sold
something (no zero-filled current-month row, unlike product/unit performance).

### unit_performance — one row per (month, business unit)
Revenue, COGS, returns, expenses, `gross_profit`, `estimated_net_profit`,
`net_margin_pct`, `return_rate_pct` — all scoped to that `month`. Always
includes all 12 business units for every month with any activity, plus the
current month (zero-filled if nothing has happened yet this month) — this is
the mart the Looker Studio "this month" scorecards should point at.

### expense_summary — one row per day × category
`transaction_count`, `total_amount`, M-Pesa/Bank split, month/week starts.

### returns_analysis — one row per return transaction
Enriched with `product_name`, `category`, and `product_return_rate_pct`
(units returned ÷ units sold per product).

### customer_insights — one row per (month, customer with a recorded phone)
`customer_phone_masked` (07XX****XX — full numbers never leave staging),
spend totals for that month, `customer_tier` (VIP ≥ 10,000 / Regular ≥ 3,000 /
Occasional) and `is_repeat_customer` evaluated within that month only (not
lifetime), `days_since_last_purchase`.
