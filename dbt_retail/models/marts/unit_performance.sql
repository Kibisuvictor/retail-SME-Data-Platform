{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'All-time performance per business unit using accurate cost prices.'
  )
}}

WITH sales_agg AS (
    SELECT
        unit,
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
    GROUP BY unit
),

returns_agg AS (
    SELECT
        unit,
        COUNT(*)                        AS total_returns_processed,
        SUM(units_returned)             AS total_units_returned,
        ROUND(SUM(return_value), 2)     AS total_return_value
    FROM {{ ref('stg_returns') }}
    WHERE unit IS NOT NULL
    GROUP BY unit
),

expenses_agg AS (
    SELECT
        unit,
        COUNT(*)                        AS total_expense_entries,
        ROUND(SUM(amount), 2)           AS total_expenses
    FROM {{ ref('stg_expenses') }}
    WHERE unit IS NOT NULL
    GROUP BY unit
),

-- ACCURATE COGS per unit using cost_price from stg_products
cogs_agg AS (
    SELECT
        s.unit,
        ROUND(SUM(s.units_sold * COALESCE(p.cost_price, 0)), 2) AS total_cogs
    FROM {{ ref('stg_sales') }} s
    LEFT JOIN {{ ref('stg_products') }} p ON s.product_key = p.product_key
    WHERE s.unit IS NOT NULL
    GROUP BY s.unit
)

SELECT
    bu.unit_name                                            AS unit,

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

FROM {{ ref('business_units') }} bu
LEFT JOIN sales_agg    s ON bu.unit_name = s.unit
LEFT JOIN returns_agg  r ON bu.unit_name = r.unit
LEFT JOIN expenses_agg e ON bu.unit_name = e.unit
LEFT JOIN cogs_agg     c ON bu.unit_name = c.unit
ORDER BY total_revenue DESC
