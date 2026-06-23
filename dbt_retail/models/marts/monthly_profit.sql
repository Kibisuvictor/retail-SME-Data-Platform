{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Monthly P&L by business unit: revenue, COGS, operating expenses, and net profit.'
  )
}}

/*
  Grain: one row per (month, unit).
  `unit` is NULL for historical rows recorded before the Business Unit field
  existed — those still roll up correctly, just not attributable to a branch.
*/

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(sale_date, MONTH)                                        AS month,
        unit,
        ROUND(SUM(net_amount), 2)                                           AS gross_revenue,
        ROUND(SUM(discount_amount), 2)                                      AS total_discounts,
        COUNT(*)                                                            AS sale_count,
        SUM(units_sold)                                                     AS units_sold
    FROM {{ ref('stg_sales') }}
    GROUP BY DATE_TRUNC(sale_date, MONTH), unit
),

monthly_returns AS (
    SELECT
        DATE_TRUNC(return_date, MONTH)          AS month,
        unit,
        ROUND(SUM(return_value), 2)             AS total_returns,
        SUM(units_returned)                     AS units_returned,
        COUNT(*)                                AS return_count
    FROM {{ ref('stg_returns') }}
    GROUP BY DATE_TRUNC(return_date, MONTH), unit
),

monthly_cogs AS (
    SELECT
        DATE_TRUNC(s.sale_date, MONTH)                                      AS month,
        s.unit,
        ROUND(
            SUM(s.units_sold * COALESCE(lc.latest_cost_price, 0)),
            2
        )                                                                   AS total_cogs
    FROM {{ ref('stg_sales') }} s
    LEFT JOIN (
        SELECT
            product_key,
            ARRAY_AGG(unit_cost ORDER BY purchase_date DESC LIMIT 1)[OFFSET(0)] AS latest_cost_price
        FROM {{ ref('stg_inventory_purchases') }}
        GROUP BY product_key
    ) lc ON s.product_key = lc.product_key
    GROUP BY DATE_TRUNC(s.sale_date, MONTH), s.unit
),

monthly_expenses AS (
    SELECT
        DATE_TRUNC(expense_date, MONTH)     AS month,
        unit,
        ROUND(SUM(amount), 2)               AS total_opex,
        COUNT(*)                            AS expense_count
    FROM {{ ref('stg_expenses') }}
    GROUP BY DATE_TRUNC(expense_date, MONTH), unit
),

-- All (month, unit) combinations seen anywhere, so a unit with e.g. expenses
-- but no sales in a given month is not silently dropped.
all_keys AS (
    SELECT month, unit FROM monthly_revenue
    UNION DISTINCT
    SELECT month, unit FROM monthly_returns
    UNION DISTINCT
    SELECT month, unit FROM monthly_expenses
)

SELECT
    k.month,
    k.unit,

    COALESCE(r.gross_revenue, 0)                                AS gross_revenue,
    COALESCE(r.total_discounts, 0)                               AS total_discounts,
    COALESCE(ret.total_returns, 0)                              AS total_returns,
    COALESCE(ret.units_returned, 0)                             AS units_returned,
    COALESCE(ret.return_count, 0)                               AS return_count,

    -- Net revenue = sales - returns
    ROUND(COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0), 2) AS net_revenue,

    COALESCE(cogs.total_cogs, 0)                                AS total_cogs,
    COALESCE(exp.total_opex, 0)                                 AS total_operating_expenses,

    -- Gross profit = net revenue - COGS
    ROUND(
        (COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0))
        - COALESCE(cogs.total_cogs, 0),
        2
    )                                                           AS gross_profit,

    -- Net profit = gross profit - opex
    ROUND(
        (COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0))
        - COALESCE(cogs.total_cogs, 0)
        - COALESCE(exp.total_opex, 0),
        2
    )                                                           AS net_profit,

    -- Net margin %
    CASE
        WHEN (COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0)) > 0
        THEN ROUND(
            (
                (COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0))
                - COALESCE(cogs.total_cogs, 0)
                - COALESCE(exp.total_opex, 0)
            ) / (COALESCE(r.gross_revenue, 0) - COALESCE(ret.total_returns, 0)) * 100,
            1
        )
        ELSE 0
    END                                                         AS net_margin_pct,

    COALESCE(r.sale_count, 0)                                   AS sale_count,
    COALESCE(r.units_sold, 0)                                   AS units_sold,
    COALESCE(exp.expense_count, 0)                              AS expense_entries

FROM all_keys k
LEFT JOIN monthly_revenue  r    ON k.month = r.month
                                AND COALESCE(k.unit, '_none_') = COALESCE(r.unit, '_none_')
LEFT JOIN monthly_returns  ret  ON k.month = ret.month
                                AND COALESCE(k.unit, '_none_') = COALESCE(ret.unit, '_none_')
LEFT JOIN monthly_cogs     cogs ON k.month = cogs.month
                                AND COALESCE(k.unit, '_none_') = COALESCE(cogs.unit, '_none_')
LEFT JOIN monthly_expenses exp  ON k.month = exp.month
                                AND COALESCE(k.unit, '_none_') = COALESCE(exp.unit, '_none_')
ORDER BY k.month DESC, k.unit
