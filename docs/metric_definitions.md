# Metric Definitions

Every number shown in Looker Studio dashboards — what it means and how it's calculated.

---

## Revenue

| Metric | Formula | Where |
|--------|---------|-------|
| Gross Revenue | SUM(units_sold × unit_price) | Before any deductions |
| Net Revenue | gross_revenue − discounts | After discounts |
| Effective Revenue | net_revenue − returns_value | **Primary revenue metric** |
| Returns Value | SUM(net_amount) WHERE is_return = TRUE | What was refunded |

---

## Profit

| Metric | Formula | Notes |
|--------|---------|-------|
| COGS | SUM(units_sold × latest_cost_price) | Cost of what was sold |
| Gross Profit | net_revenue − COGS | Before operating expenses |
| Net Profit | gross_profit − operating_expenses | **What the business keeps** |
| Gross Margin % | (gross_profit / net_revenue) × 100 | Higher = more profitable per sale |
| Net Margin % | (net_profit / net_revenue) × 100 | Overall business profitability |

---

## Inventory

| Metric | Formula | Notes |
|--------|---------|-------|
| Stock on Hand | total_purchased − total_sold + total_returned | Never manually entered — always derived |
| Inventory Value at Cost | stock_on_hand × latest_cost_price | Cash tied up in stock |
| Inventory Value at Retail | stock_on_hand × selling_price | What stock would sell for |
| Needs Reorder | stock_on_hand ≤ reorder_level | TRUE = buy more |

---

## Customer Tiers

| Tier | Threshold | Action |
|------|-----------|--------|
| VIP | Total spent ≥ KES 10,000 | Prioritise, offer loyalty |
| Regular | KES 3,000–9,999 | Nurture, encourage repeat |
| Occasional | < KES 3,000 | Convert to regular |

---

## FAQs

**Q: Revenue today looks lower than expected even with many sales.**  
Check returns. A large return reduces effective revenue.

**Q: A product shows negative stock.**  
A purchase was not recorded. Add the missing purchase via the Inventory Purchase Form and re-run dbt.

**Q: Net profit is unexpectedly high.**  
Check if all expenses for the month have been entered. Missing expenses make profit appear higher than it is.

**Q: Customer insights shows fewer customers than expected.**  
Only sales where a phone number was captured are included. Sales without a phone are not in customer_insights but are still counted in all revenue figures.
