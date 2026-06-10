{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Daily sales aggregates. Returns sourced from dedicated Returns Form.'
  )
}}

/*
  stg_sales contains only sales; returns come from stg_returns (dedicated form).
*/

WITH daily_sales AS (
    SELECT
        sale_date,
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
    GROUP BY sale_date
),

daily_returns AS (
    SELECT
        return_date                         AS sale_date,
        SUM(units_returned)                 AS units_returned,
        ROUND(SUM(return_value), 2)         AS returns_value,
        COUNT(*)                            AS return_transaction_count
    FROM {{ ref('stg_returns') }}
    GROUP BY return_date
)

SELECT
    s.sale_date,

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
    EXTRACT(DAYOFWEEK FROM s.sale_date)     AS day_of_week,
    EXTRACT(DAY FROM s.sale_date)           AS day_of_month,
    DATE_TRUNC(s.sale_date, WEEK(MONDAY))   AS week_start,
    DATE_TRUNC(s.sale_date, MONTH)          AS month_start

FROM daily_sales s
LEFT JOIN daily_returns r ON s.sale_date = r.sale_date
ORDER BY s.sale_date DESC
