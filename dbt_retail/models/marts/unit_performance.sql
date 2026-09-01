{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-month performance per business unit using accurate cost prices.'
  )
}}

/*
  Grain: one row per (month, unit) — always all business units, for every
  month with any sales/returns/expense activity across the business, plus
  the current calendar month, always, even before any activity happens in
  it. This lets Looker Studio default a date filter to "This month" instead
  of showing all-time cumulative totals.
*/

WITH sales_agg AS (
    SELECT
        unit,
        DATE_TRUNC(sale_date, MONTH)    AS month,
        COUNT(*)                        AS total_transactions,
        SUM(units_sold)                 AS total_units_sold,
        ROUND(SUM(net_amount), 2)       AS total_revenue,
        ROUND(SUM(discount_amount), 2)  AS total_discounts,
        ROUND(AVG(net_amount), 2)       AS avg_transaction_value,
        COUNT(DISTINCT salesperson_name) AS salespeople_count,
        COUNT(DISTINCT sale_date)       AS active_days,
        MIN(sale_date)                  AS first_sale_date,
        MAX(sale_date)                  AS last_sale_date
    FROM {{ ref('stg_sales') }}
    WHERE unit IS NOT NULL
    GROUP BY unit, DATE_TRUNC(sale_date, MONTH)
),

returns_agg AS (
    SELECT
        unit,
        DATE_TRUNC(return_date, MONTH)  AS month,
        COUNT(*)                        AS total_returns_processed,
        SUM(units_returned)             AS total_units_returned,
        ROUND(SUM(return_value), 2)     AS total_return_value
    FROM {{ ref('stg_returns') }}
    WHERE unit IS NOT NULL
    GROUP BY unit, DATE_TRUNC(return_date, MONTH)
),

expenses_agg AS (
    SELECT
        unit,
        DATE_TRUNC(expense_date, MONTH) AS month,
        COUNT(*)                        AS total_expense_entries,
        ROUND(SUM(amount), 2)           AS total_expenses
    FROM {{ ref('stg_expenses') }}
    WHERE unit IS NOT NULL
    GROUP BY unit, DATE_TRUNC(expense_date, MONTH)
),

-- ACCURATE COGS per unit using cost_price from stg_products
cogs_agg AS (
    SELECT
        s.unit,
        DATE_TRUNC(s.sale_date, MONTH)                           AS month,
        ROUND(SUM(s.units_sold * COALESCE(p.cost_price, 0)), 2)  AS total_cogs
    FROM {{ ref('stg_sales') }} s
    LEFT JOIN {{ ref('stg_products') }} p ON s.product_key = p.product_key
    WHERE s.unit IS NOT NULL
    GROUP BY s.unit, DATE_TRUNC(s.sale_date, MONTH)
),

-- Every month with any activity, plus the current month, so every unit
-- always has a (possibly all-zero) row set for "this month".
all_months AS (
    SELECT month FROM sales_agg
    UNION DISTINCT
    SELECT month FROM returns_agg
    UNION DISTINCT
    SELECT month FROM expenses_agg
    UNION DISTINCT
    SELECT DATE_TRUNC(CURRENT_DATE(), MONTH)
),

unit_months AS (
    SELECT bu.unit_name AS unit, m.month
    FROM {{ ref('business_units') }} bu
    CROSS JOIN all_months m
)

SELECT
    um.month,
    um.unit,

    COALESCE(s.total_transactions, 0)                       AS total_transactions,
    COALESCE(s.total_units_sold, 0)                         AS total_units_sold,
    COALESCE(s.total_revenue, 0)                            AS total_revenue,
    COALESCE(s.total_discounts, 0)                          AS total_discounts,
    COALESCE(s.avg_transaction_value, 0)                    AS avg_transaction_value,
    COALESCE(s.salespeople_count, 0)                        AS salespeople_count,
    COALESCE(s.active_days, 0)                              AS active_days,
    s.first_sale_date,
    s.last_sale_date,

    COALESCE(r.total_returns_processed, 0)                  AS total_returns_processed,
    COALESCE(r.total_units_returned, 0)                     AS total_units_returned,
    COALESCE(r.total_return_value, 0)                       AS total_return_value,

    COALESCE(e.total_expense_entries, 0)                    AS total_expense_entries,
    COALESCE(e.total_expenses, 0)                           AS total_expenses,

    COALESCE(c.total_cogs, 0)                               AS total_cogs,

    -- Gross profit = revenue - returns - COGS
    ROUND(
        COALESCE(s.total_revenue, 0)
        - COALESCE(r.total_return_value, 0)
        - COALESCE(c.total_cogs, 0), 2
    )                                                       AS gross_profit,

    -- Net profit = gross profit - operating expenses
    ROUND(
        COALESCE(s.total_revenue, 0)
        - COALESCE(r.total_return_value, 0)
        - COALESCE(c.total_cogs, 0)
        - COALESCE(e.total_expenses, 0), 2
    )                                                       AS estimated_net_profit,

    CASE
        WHEN COALESCE(s.total_revenue, 0) > 0
        THEN ROUND(
            (
                COALESCE(s.total_revenue, 0)
                - COALESCE(r.total_return_value, 0)
                - COALESCE(c.total_cogs, 0)
                - COALESCE(e.total_expenses, 0)
            ) / s.total_revenue * 100, 1
        )
        ELSE NULL
    END                                                     AS net_margin_pct,

    CASE
        WHEN COALESCE(s.total_units_sold, 0) > 0
        THEN ROUND(
            COALESCE(r.total_units_returned, 0)
            / s.total_units_sold * 100, 2
        )
        ELSE NULL
    END                                                     AS return_rate_pct

FROM unit_months um
LEFT JOIN sales_agg    s ON um.unit = s.unit AND um.month = s.month
LEFT JOIN returns_agg  r ON um.unit = r.unit AND um.month = r.month
LEFT JOIN expenses_agg e ON um.unit = e.unit AND um.month = e.month
LEFT JOIN cogs_agg     c ON um.unit = c.unit AND um.month = c.month
ORDER BY um.month DESC, total_revenue DESC
