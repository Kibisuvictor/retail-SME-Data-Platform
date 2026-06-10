# Data Dictionary — GCP Edition

All tables across `retail_raw`, `retail_staging`, and `retail_marts` datasets in BigQuery.

---

## Dataset: retail_raw

External tables — live reads from Google Sheets. All columns are STRING.

| Table | Source Sheet Tab | Description |
|-------|-----------------|-------------|
| `sales_raw` | Sales | Raw sales transactions |
| `expenses_raw` | Expenses | Raw expense records |
| `inventory_purchases_raw` | Inventory Purchases | Raw stock purchase records |
| `products_raw` | Products | Raw product master data |

> No transformations happen here. These tables exist purely to give dbt a BigQuery-native source to query.

---

## Dataset: retail_staging

Cleaned, typed, validated tables. Built by dbt from `retail_raw`.

### stg_products

| Column | Type | Description |
|--------|------|-------------|
| `product_key` | STRING | Slug: "omo_detergent_1kg" — join key across all models |
| `product_name` | STRING | Display name |
| `category` | STRING | One of 12 categories |
| `unit_of_measure` | STRING | Piece / Kg / Litre / Pack |
| `selling_price` | NUMERIC | Current retail price in KES |
| `reorder_level` | INT64 | Alert threshold (default 5) |
| `is_active` | BOOL | True if currently sold |
| `submitted_at` | TIMESTAMP | Form submission time |

### stg_sales

| Column | Type | Description |
|--------|------|-------------|
| `sale_id` | STRING | MD5 surrogate key |
| `sale_date` | DATE | Date of sale |
| `salesperson_name` | STRING | Uppercase name |
| `product_key` | STRING | FK → stg_products |
| `units_sold` | INT64 | Units in transaction |
| `unit_price` | NUMERIC | Price per unit in KES |
| `discount_amount` | NUMERIC | Discount in KES |
| `payment_method` | STRING | M-Pesa or Bank |
| `is_return` | BOOL | True = return transaction |
| `customer_phone` | STRING | Validated 07XXXXXXXX or NULL |
| `gross_amount` | NUMERIC | units_sold × unit_price |
| `net_amount` | NUMERIC | gross_amount − discount_amount |
| `notes` | STRING | Optional notes |
| `submitted_at` | TIMESTAMP | Form submission time |

### stg_expenses

| Column | Type | Description |
|--------|------|-------------|
| `expense_id` | STRING | MD5 surrogate key |
| `expense_date` | DATE | Date expense occurred |
| `expense_category` | STRING | Category |
| `amount` | NUMERIC | Amount in KES |
| `description` | STRING | What it was for |
| `paid_via` | STRING | M-Pesa or Bank |
| `recorded_by` | STRING | Who recorded it |
| `submitted_at` | TIMESTAMP | Form submission time |

### stg_inventory_purchases

| Column | Type | Description |
|--------|------|-------------|
| `purchase_id` | STRING | MD5 surrogate key |
| `purchase_date` | DATE | Date stock received |
| `product_key` | STRING | FK → stg_products |
| `units_purchased` | INT64 | Units received |
| `unit_cost` | NUMERIC | Cost price per unit |
| `total_cost` | NUMERIC | units_purchased × unit_cost |
| `supplier_name` | STRING | Supplier |
| `payment_method` | STRING | M-Pesa or Bank |
| `notes` | STRING | Optional notes |
| `submitted_at` | TIMESTAMP | Form submission time |

---

## Dataset: retail_marts

Business-ready aggregated tables. Queried directly by Looker Studio.

### inventory_position

| Column | Type | Description |
|--------|------|-------------|
| `product_key` | STRING | PK |
| `product_name` | STRING | Display name |
| `category` | STRING | Category |
| `selling_price` | NUMERIC | Current retail price |
| `reorder_level` | INT64 | Alert threshold |
| `total_purchased` | INT64 | All-time units received |
| `total_sold` | INT64 | All-time units sold |
| `total_returned` | INT64 | All-time units returned |
| `stock_on_hand` | INT64 | **Current stock** (purchases − sold + returned) |
| `inventory_value_at_cost` | NUMERIC | Stock × latest cost price |
| `inventory_value_at_retail` | NUMERIC | Stock × selling price |
| `stock_status` | STRING | In Stock / Low Stock / Out of Stock |
| `needs_reorder` | BOOL | True when stock ≤ reorder_level |
| `last_purchase_date` | DATE | Last restock date |
| `latest_unit_cost` | NUMERIC | Most recent cost price |

### daily_sales_summary

| Column | Type | Description |
|--------|------|-------------|
| `sale_date` | DATE | PK — the day |
| `transaction_count` | INT64 | Number of entries |
| `units_sold` | INT64 | Total units (excl. returns) |
| `gross_revenue` | NUMERIC | Revenue before discounts |
| `net_revenue` | NUMERIC | After discounts |
| `effective_revenue` | NUMERIC | After discounts and returns |
| `mpesa_revenue` | NUMERIC | Via M-Pesa |
| `bank_revenue` | NUMERIC | Via Bank |
| `day_of_month` | INT64 | 1–31 |
| `week_start` | DATE | Monday of that week |
| `month_start` | DATE | First of that month |

### monthly_profit

| Column | Type | Description |
|--------|------|-------------|
| `month` | DATE | First day of the month |
| `gross_revenue` | NUMERIC | Total revenue |
| `total_returns` | NUMERIC | Returns value |
| `net_revenue` | NUMERIC | After returns |
| `total_cogs` | NUMERIC | Cost of goods sold |
| `total_operating_expenses` | NUMERIC | Opex from expenses |
| `gross_profit` | NUMERIC | net_revenue − COGS |
| `net_profit` | NUMERIC | gross_profit − opex |
| `net_margin_pct` | NUMERIC | Net profit as % of revenue |

### customer_insights

| Column | Type | Description |
|--------|------|-------------|
| `customer_phone_masked` | STRING | 07XX****XX — masked for privacy |
| `total_transactions` | INT64 | Purchases |
| `total_spent` | NUMERIC | Total KES spent |
| `customer_tier` | STRING | VIP / Regular / Occasional |
| `is_repeat_customer` | BOOL | Purchased on >1 day |
| `days_since_last_purchase` | INT64 | Recency |
