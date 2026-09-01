# Looker Studio Setup Guide

Complete guide to building all 9 dashboards.  
Dashboards work on **any phone browser** — share via link, no login required for viewers.

---

## Connecting Looker Studio to BigQuery

### Step 1 — Open Looker Studio
Go to [lookerstudio.google.com](https://lookerstudio.google.com)  
Sign in with the same Google account used for BigQuery.

### Step 2 — Create a new report
1. Click **Create** → **Report**
2. In the data source panel, click **BigQuery**
3. Select:
   - **Project:** your GCP project ID
   - **Dataset:** `retail_marts`
   - **Table:** `daily_sales_summary`
4. Click **Add** → **Add to Report**

You now have a blank report connected to BigQuery.

### Step 3 — Add more data sources
You need one data source per mart table. Add each:

1. Click **Resource** → **Manage added data sources** → **Add a data source**
2. Repeat for each table:
   - `retail_marts.inventory_position`
   - `retail_marts.product_performance`
   - `retail_marts.salesperson_performance`
   - `retail_marts.unit_performance`
   - `retail_marts.expense_summary`
   - `retail_marts.monthly_profit`
   - `retail_marts.customer_insights`
   - `retail_marts.returns_analysis`

### A note on `month` filtering

`product_performance`, `salesperson_performance`, `unit_performance`, and
`customer_insights` each carry a `month` column (one row per month × entity,
not an all-time total). On any page built from these, add a **Date Range
Control** (Insert → Date range control), set its field to `month`, and set
its default range to **"This month"**. Without that control the charts sum
across every month ever recorded — with it, the page automatically shows
only the current month and rolls over on its own when a new month starts, no
manual re-filtering needed. Pick a prior month from the control any time you
want to look back.

---

## Dashboard 1: Daily Operations (Owner's Morning View)

**Purpose:** Owner opens this on their phone every morning.  
**Make this your report's first page.**

### Layout (mobile-optimised — use narrow cards)

**Card 1 — Today's Revenue**
- Chart type: Scorecard
- Data source: `daily_sales_summary`
- Metric: `effective_revenue`
- Filter: `sale_date` = Today
- Style: Large number, green colour, label "Today's Revenue (KES)"

**Card 2 — Today's Transactions**
- Chart type: Scorecard
- Metric: `transaction_count`
- Filter: `sale_date` = Today

**Card 3 — Today's Units Sold**
- Chart type: Scorecard
- Metric: `units_sold`
- Filter: `sale_date` = Today

**Card 4 — M-Pesa vs Bank Today**
- Chart type: Pie chart
- Dimension: Payment method (create a calculated field — see below)
- Metrics: `mpesa_revenue`, `bank_revenue`

> Calculated field for payment split:
> Create two scorecards instead:
> - Card A: metric = `mpesa_revenue`, label "M-Pesa Today"
> - Card B: metric = `bank_revenue`, label "Bank Today"

**Card 5 — Low Stock Alerts**
- Chart type: Table
- Data source: `inventory_position`
- Dimension: `product_name`, `category`, `stock_on_hand`, `reorder_level`
- Filter: `needs_reorder` = true
- Sort: `stock_on_hand` ascending
- Style: Highlight rows where `stock_status` = "Out of Stock" in red

**Card 6 — Revenue Last 7 Days**
- Chart type: Bar chart
- Data source: `daily_sales_summary`
- Dimension: `sale_date`
- Metric: `effective_revenue`
- Filter: `sale_date` in last 7 days
- Sort: `sale_date` ascending

---

## Dashboard 2: Sales Trends

**Purpose:** Weekly review — is the business growing?

**Card 1 — Daily Revenue Last 30 Days (Line Chart)**
- Data: `daily_sales_summary`
- Dimension: `sale_date`
- Metric: `effective_revenue`
- Default date range: Last 30 days

**Card 2 — Weekly Revenue (Bar Chart)**
- Data: `daily_sales_summary`
- Dimension: `week_start`
- Metric: SUM(`effective_revenue`) — aggregated by week
- Date range: Last 12 weeks

**Card 3 — Monthly Revenue (Bar Chart)**
- Data: `daily_sales_summary`
- Dimension: `month_start`
- Metric: SUM(`effective_revenue`)

**Card 4 — Revenue by Payment Method (Stacked Bar)**
- Data: `daily_sales_summary`
- Dimension: `month_start`
- Metrics: `mpesa_revenue`, `bank_revenue`
- Chart type: Stacked bar

**Card 5 — Sales by Day of Month (Bar Chart)**
- Data: `daily_sales_summary`
- Dimension: `day_of_month`
- Metric: AVG(`effective_revenue`)
- Note: This clearly shows the beginning/end-of-month spike

**Card 6 — Returns Trend (Line Chart)**
- Data: `daily_sales_summary`
- Dimension: `sale_date`
- Metric: `returns_value`

---

## Dashboard 3: Product Performance

**Purpose:** Which products to promote, reorder, or drop.

**Add a Date Range Control at the top of this page** — field `month`,
default "This month" (see note above). Every card below reads from
`product_performance`, so this one control scopes the whole page to the
current month; switch it to a prior month to look back.

**Card 1 — Top 10 Products by Revenue (Horizontal Bar)**
- Data: `product_performance`
- Dimension: `product_name`
- Metric: `total_revenue`
- Rows: 10
- Sort: `total_revenue` descending

**Card 2 — Bottom 10 Products (Horizontal Bar)**
- Same as above but sort ascending, filter `total_transactions` > 0

**Card 3 — Most Profitable Products (Bar Chart)**
- Data: `product_performance`
- Dimension: `product_name`
- Metric: `estimated_gross_profit`
- Rows: 10, sort descending

**Card 4 — Revenue by Category (Donut Chart)**
- Data: `product_performance`
- Dimension: `category`
- Metric: SUM(`total_revenue`)

**Card 5 — Full Product Table**
- Chart type: Table with sorting
- Columns: `product_name`, `category`, `total_units_sold`, `total_revenue`, `gross_margin_pct`, `latest_cost_price`
- Sort: `total_revenue` descending

---

## Dashboard 4: Inventory

**Purpose:** Stock decisions — what to buy and what's running low.

**Card 1 — Total Inventory Value at Cost (Scorecard)**
- Data: `inventory_position`
- Metric: SUM(`inventory_value_at_cost`)
- Label: "Stock Value at Cost (KES)"

**Card 2 — Items Needing Reorder (Scorecard)**
- Data: `inventory_position`
- Metric: COUNT(`product_key`)
- Filter: `needs_reorder` = true
- Style: Orange/red when > 0

**Card 3 — Inventory Table (full)**
- Columns: `product_name`, `category`, `stock_on_hand`, `reorder_level`, `stock_status`, `inventory_value_at_cost`, `last_purchase_date`
- Conditional formatting:
  - Red: `stock_status` = "Out of Stock"
  - Orange: `stock_status` = "Low Stock"
  - Green: `stock_status` = "In Stock"
- Sort: `stock_status` ascending (Out of Stock first)

**Card 4 — Fast Moving Products (Bar)**
- Data: `product_performance`
- Dimension: `product_name`
- Metric: `total_units_sold`
- Rows: 15, sort descending
- Filter: `month` = this month (this page has no page-level date control, so
  add the filter directly on this card — otherwise it sums units sold across
  every month ever recorded)

---

## Dashboard 5: Expenses & Profit

**Purpose:** Monthly financial health check.

**Card 1 — Monthly Net Profit (Line Chart)**
- Data: `monthly_profit`
- Dimension: `month`
- Metric: `net_profit`
- Add a reference line at 0 (Configuration → Reference lines)
- Colour: green above 0, red below 0

**Card 2 — Monthly P&L Table**
- Columns: `month`, `gross_revenue`, `total_returns`, `total_cogs`, `total_operating_expenses`, `gross_profit`, `net_profit`, `net_margin_pct`
- Sort: `month` descending

**Card 3 — Expenses This Month by Category (Donut)**
- Data: `expense_summary`
- Dimension: `expense_category`
- Metric: SUM(`total_amount`)
- Date filter: current month

**Card 4 — Monthly Expense Trend (Bar)**
- Data: `expense_summary`
- Dimension: `month_start`
- Metric: SUM(`total_amount`)

---

## Dashboard 6: Customers

**Purpose:** Who are the best customers?

**Add a Date Range Control at the top of this page** — field `month`,
default "This month" (see note above). `customer_tier` and
`is_repeat_customer` are evaluated per month, e.g. "VIP this month," not
lifetime — switch the control to a prior month to see that month's tiers.

**Card 1 — Total Customers Tracked (Scorecard)**
- Data: `customer_insights`
- Metric: COUNT(`customer_phone_masked`)

**Card 2 — Repeat Customers (Scorecard)**
- Metric: COUNT(`customer_phone_masked`)
- Filter: `is_repeat_customer` = true

**Card 3 — Customer Tiers (Donut)**
- Dimension: `customer_tier`
- Metric: COUNT(`customer_phone_masked`)

**Card 4 — Top Customers Table**
- Columns: `customer_phone_masked`, `customer_tier`, `total_transactions`, `total_spent`, `avg_transaction_value`, `last_purchase_date`, `days_since_last_purchase`
- Sort: `total_spent` descending
- Rows: 20

---

## Dashboard 7: Salesperson Performance

**Purpose:** Track who is selling, how much, and how.

**Add a Date Range Control at the top of this page** — field `month`,
default "This month" (see note above).

**Card 1 — Revenue by Salesperson (Bar)**
- Data: `salesperson_performance`
- Dimension: `salesperson_name`
- Metric: `total_revenue`

**Card 2 — Transactions by Salesperson (Bar)**
- Metric: `total_transactions`

**Card 3 — Full Table**
- Columns: `salesperson_name`, `total_transactions`, `total_units_sold`, `total_revenue`, `total_discounts_given`, `avg_transaction_value`, `active_days`

---

## Dashboard 9: Business Unit Comparison

**Purpose:** "Which unit performs better this month" — the question that
used to require manually filtering an all-time total. Add
`retail_marts.unit_performance` as a data source if you haven't already.

**Add a Date Range Control at the top of this page** — field `month`,
default "This month". Every card below reads from `unit_performance`, which
already always lists all 12 units for the selected month (zero-filled if a
unit had no activity yet) — no extra "show all units" filter needed.

**Card 1 — Revenue by Unit This Month (Bar Chart)**
- Data: `unit_performance`
- Dimension: `unit`
- Metric: `total_revenue`
- Sort: `total_revenue` descending

**Card 2 — Net Profit by Unit This Month (Bar Chart)**
- Metric: `estimated_net_profit`
- Colour: green above 0, red below 0

**Card 3 — Full Unit Comparison Table**
- Columns: `unit`, `total_transactions`, `total_revenue`, `total_cogs`, `total_expenses`, `gross_profit`, `estimated_net_profit`, `net_margin_pct`, `return_rate_pct`
- Sort: `total_revenue` descending

**Card 4 — Revenue Trend by Unit (Line Chart)**
- Remove the page's date control's effect on this one card (or duplicate the
  chart on a page without the control): dimension `month`, breakdown
  dimension `unit`, metric `total_revenue` — shows month-over-month
  comparison across units instead of a single month.

---

## Dashboard 8: Returns Analysis

**Purpose:** Understand why items come back, which products are problematic, and how refunds are being issued.

**Card 1 — Total Return Value This Month (Scorecard)**
- Data: `returns_analysis`
- Metric: SUM(`return_value`)
- Filter: `month_start` = current month
- Style: Orange colour — returns reduce profit

**Card 2 — Total Units Returned This Month (Scorecard)**
- Metric: SUM(`units_returned`)
- Filter: `month_start` = current month

**Card 3 — Returns by Reason (Donut Chart)**
- Dimension: `return_reason`
- Metric: SUM(`units_returned`)
- Note: Large "Defective" slice = supplier quality issue; large "Customer Changed Mind" = possible mis-selling

**Card 4 — Returns by Refund Method (Donut Chart)**
- Dimension: `refund_method`
- Metric: SUM(`return_value`)
- Note: High "No Refund" may indicate disputes; high "Store Credit" is healthy

**Card 5 — Most Returned Products (Horizontal Bar)**
- Dimension: `product_name`
- Metric: SUM(`units_returned`)
- Rows: 10, sort descending
- Note: Products appearing here consistently may have quality issues

**Card 6 — Monthly Returns Trend (Line Chart)**
- Dimension: `month_start`
- Metric: SUM(`return_value`)
- Add a secondary metric: SUM(`units_returned`)
- Note: Rising trend needs investigation

**Card 7 — Returns by Category (Bar Chart)**
- Dimension: `category`
- Metric: SUM(`return_value`)

**Card 8 — Returns vs Sales by Salesperson (Grouped Bar)**
- Data: join `salesperson_performance` and a returns-by-salesperson query
- Or use two separate bar charts side by side:
  - Bar A: `salesperson_performance.total_revenue`
  - Bar B: `returns_analysis` grouped by `salesperson_name`, metric SUM(`return_value`)

**Card 9 — Full Returns Table**
- Data: `returns_analysis`
- Columns: `return_date`, `product_name`, `category`, `units_returned`, `return_value`, `return_reason`, `refund_method`, `salesperson_name`
- Sort: `return_date` descending
- Enable search/filter so owner can look up specific returns

---

## Daily Operations Dashboard — Add Returns Card

Go back to Dashboard 1 and add one more card:

**Today's Returns (Scorecard)**
- Data: `returns_analysis`
- Metric: SUM(`return_value`)
- Filter: `return_date` = Today
- Style: Orange, label "Today's Returns (KES)"
- Place it next to Today's Revenue so the owner sees both at a glance

---

## Making Dashboards Mobile-Friendly

Looker Studio auto-adapts to phone screens. To optimise:

1. **Use the mobile layout toggle** (View → Mobile layout)
2. **Stack cards vertically** rather than side by side
3. **Use large fonts** for scorecard numbers (24pt minimum)
4. **Limit table columns** to 4–5 on mobile views
5. Keep the Daily Operations dashboard as **Page 1** — it's the one the owner opens daily

---

## Sharing Dashboards with the Owner

### Option A — Shareable link (simplest)
1. Click **Share** → **Manage access**
2. Set to **Anyone with the link can view**
3. Copy link → send to owner via WhatsApp
4. Owner bookmarks it on their phone

### Option B — Schedule email delivery
1. Click **Share** → **Schedule email delivery**
2. Set: Daily at 7:00 AM
3. Recipient: owner's email
4. Format: PDF attachment
5. Owner receives a daily PDF summary in their inbox automatically

### Option C — Add to phone home screen
On Android or iPhone:
1. Open the dashboard link in Chrome
2. Tap the three dots (⋮) menu
3. Tap **Add to Home screen**
4. The dashboard appears as an app icon

---

## Refreshing Data

Data flows on the daily pipeline schedule, not live:

1. **21:00 EAT** — GitHub Actions runs the ETL (Sheets → `retail_raw`) then dbt
   rebuilds `retail_staging` and `retail_marts`.
2. Looker Studio queries the marts, but **caches results (default up to 12 hours)**.

**One-time setting:** Resource → Manage added data sources → Edit each source →
set **Data freshness** to **1 hour**. Dashboards opened in the morning then always
show the previous evening's complete data. Viewers can also force-refresh with
the ⟳ icon at the top of the report.

No GCP-side configuration is needed for freshness — only this Looker Studio setting.
