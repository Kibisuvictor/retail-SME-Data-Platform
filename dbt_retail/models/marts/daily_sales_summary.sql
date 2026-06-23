{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Daily sales aggregates by business unit. Returns sourced from dedicated Returns Form.'
  )
}}

/*
  Grain: one row per (sale_date, unit).
  stg_sales contains only sales; returns come from stg_returns (dedicated form).
  `unit` will be NULL for historical rows recorded before the Business Unit
  field existed on the Forms — these still aggregate correctly, they just
  won't be attributable to a specific branch when filtering by unit.
*/

WITH daily_sales AS (
    SELECT
        sale_date,
        unit,
        COUNT(*)                                                        AS transaction_count,
        SUM(units_sold)                                                 AS units_sold,
        ROUND(SUM(gross_amount), 2)                                     AS gross_revenue,
        ROUND(SUM(discount_amount), 2)                                  AS total_discounts,
        ROUND(SUM(net_amount), 2)                                       AS net_revenue,
        ROUND(SUM(CASE WHEN payment_method = 'M-Pesa'
                       THEN net_amount ELSE 0 END), 2)                  AS mpesa_revenue,
        ROUND(SUM(CASE WHEN payment_method = 'Bank'
                       THEN net_amount ELSE 0 END), 2)                  AS bank_revenue,
        COUNT(DISTINCT customer_phone)                                  AS unique_customers_with_phone,
        COUNT(DISTINCT salesperson_name)                                AS active_salespeople
    FROM {{ ref('stg_sales') }}
    GROUP BY sale_date, unit
),

daily_returns AS (
    SELECT
        return_date                         AS sale_date,
        unit,
        SUM(units_returned)                 AS units_returned,
        ROUND(SUM(return_value), 2)         AS returns_value,
        COUNT(*)                            AS return_transaction_count
    FROM {{ ref('stg_returns') }}
    GROUP BY return_date, unit
),

-- All (date, unit) combinations seen in either sales or returns, so a unit
-- with returns but no sales on a given day (or vice versa) is not dropped.
all_keys AS (
    SELECT sale_date, unit FROM daily_sales
    UNION DISTINCT
    SELECT sale_date, unit FROM daily_returns
)

SELECT
    k.sale_date,
    k.unit,

    -- Sales
    COALESCE(s.transaction_count, 0)        AS transaction_count,
    COALESCE(s.units_sold, 0)               AS units_sold,
    COALESCE(s.gross_revenue, 0)            AS gross_revenue,
    COALESCE(s.total_discounts, 0)          AS total_discounts,
    COALESCE(s.net_revenue, 0)              AS net_revenue,

    -- Returns (from dedicated form)
    COALESCE(r.units_returned, 0)           AS units_returned,
    COALESCE(r.returns_value, 0)            AS returns_value,
    COALESCE(r.return_transaction_count, 0) AS return_transaction_count,

    -- Effective revenue = sales minus returns
    ROUND(
        COALESCE(s.net_revenue, 0)
        - COALESCE(r.returns_value, 0),
        2
    )                                       AS effective_revenue,

    -- Payment split
    COALESCE(s.mpesa_revenue, 0)            AS mpesa_revenue,
    COALESCE(s.bank_revenue, 0)             AS bank_revenue,

    COALESCE(s.unique_customers_with_phone, 0) AS unique_customers_with_phone,
    COALESCE(s.active_salespeople, 0)          AS active_salespeople,

    -- Date dimensions for Looker Studio filters
    EXTRACT(DAYOFWEEK FROM k.sale_date)     AS day_of_week,
    EXTRACT(DAY FROM k.sale_date)           AS day_of_month,
    DATE_TRUNC(k.sale_date, WEEK(MONDAY))   AS week_start,
    DATE_TRUNC(k.sale_date, MONTH)          AS month_start

FROM all_keys k
LEFT JOIN daily_sales   s ON k.sale_date = s.sale_date
                          AND COALESCE(k.unit, '_none_') = COALESCE(s.unit, '_none_')
LEFT JOIN daily_returns r ON k.sale_date = r.sale_date
                          AND COALESCE(k.unit, '_none_') = COALESCE(r.unit, '_none_')
ORDER BY k.sale_date DESC, k.unit
