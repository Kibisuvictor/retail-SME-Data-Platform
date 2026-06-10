{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Monthly P&L: revenue, COGS, operating expenses, and net profit. Returns from dedicated form.'
  )
}}

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(sale_date, MONTH)                                        AS month,
        ROUND(SUM(net_amount), 2)                                           AS gross_revenue,
        ROUND(SUM(discount_amount), 2)                                      AS total_discounts,
        COUNT(*)                                                            AS sale_count,
        SUM(units_sold)                                                     AS units_sold
    FROM {{ ref('stg_sales') }}
    GROUP BY DATE_TRUNC(sale_date, MONTH)
),

monthly_returns AS (
    SELECT
        DATE_TRUNC(return_date, MONTH)          AS month,
        ROUND(SUM(return_value), 2)             AS total_returns,
        SUM(units_returned)                     AS units_returned,
        COUNT(*)                                AS return_count
    FROM {{ ref('stg_returns') }}
    GROUP BY DATE_TRUNC(return_date, MONTH)
),

monthly_cogs AS (
    SELECT
        DATE_TRUNC(s.sale_date, MONTH)                                      AS month,
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
    GROUP BY DATE_TRUNC(s.sale_date, MONTH)
),

monthly_expenses AS (
    SELECT
        DATE_TRUNC(expense_date, MONTH)     AS month,
        ROUND(SUM(amount), 2)               AS total_opex,
        COUNT(*)                            AS expense_count
    FROM {{ ref('stg_expenses') }}
    GROUP BY DATE_TRUNC(expense_date, MONTH)
)

SELECT
    r.month,

    r.gross_revenue,
    r.total_discounts,
    COALESCE(ret.total_returns, 0)                              AS total_returns,
    COALESCE(ret.units_returned, 0)                             AS units_returned,
    COALESCE(ret.return_count, 0)                               AS return_count,

    -- Net revenue = sales - returns
    ROUND(r.gross_revenue - COALESCE(ret.total_returns, 0), 2)  AS net_revenue,

    COALESCE(cogs.total_cogs, 0)                                AS total_cogs,
    COALESCE(exp.total_opex, 0)                                 AS total_operating_expenses,

    -- Gross profit = net revenue - COGS
    ROUND(
        (r.gross_revenue - COALESCE(ret.total_returns, 0))
        - COALESCE(cogs.total_cogs, 0),
        2
    )                                                           AS gross_profit,

    -- Net profit = gross profit - opex
    ROUND(
        (r.gross_revenue - COALESCE(ret.total_returns, 0))
        - COALESCE(cogs.total_cogs, 0)
        - COALESCE(exp.total_opex, 0),
        2
    )                                                           AS net_profit,

    -- Net margin %
    CASE
        WHEN (r.gross_revenue - COALESCE(ret.total_returns, 0)) > 0
        THEN ROUND(
            (
                (r.gross_revenue - COALESCE(ret.total_returns, 0))
                - COALESCE(cogs.total_cogs, 0)
                - COALESCE(exp.total_opex, 0)
            ) / (r.gross_revenue - COALESCE(ret.total_returns, 0)) * 100,
            1
        )
        ELSE 0
    END                                                         AS net_margin_pct,

    r.sale_count,
    r.units_sold,
    COALESCE(exp.expense_count, 0)                              AS expense_entries

FROM monthly_revenue r
LEFT JOIN monthly_returns  ret  ON r.month = ret.month
LEFT JOIN monthly_cogs     cogs ON r.month = cogs.month
LEFT JOIN monthly_expenses exp  ON r.month = exp.month
ORDER BY r.month DESC
