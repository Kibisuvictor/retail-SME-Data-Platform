{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-salesperson performance. Returns processed from dedicated Returns Form.'
  )
}}

WITH sales_agg AS (
    SELECT
        salesperson_name,
        COUNT(*)                                AS total_transactions,
        COUNT(DISTINCT sale_date)               AS active_days,
        SUM(units_sold)                         AS total_units_sold,
        ROUND(SUM(net_amount), 2)               AS total_revenue,
        ROUND(SUM(discount_amount), 2)          AS total_discounts_given,
        ROUND(AVG(net_amount), 2)               AS avg_transaction_value,
        ROUND(SUM(CASE WHEN payment_method = 'M-Pesa'
                       THEN net_amount ELSE 0 END), 2)  AS mpesa_revenue,
        ROUND(SUM(CASE WHEN payment_method = 'Bank'
                       THEN net_amount ELSE 0 END), 2)  AS bank_revenue,
        MIN(sale_date)                          AS first_sale_date,
        MAX(sale_date)                          AS last_sale_date
    FROM {{ ref('stg_sales') }}
    GROUP BY salesperson_name
),

returns_agg AS (
    SELECT
        salesperson_name,
        COUNT(*)                                AS total_returns_processed,
        SUM(units_returned)                     AS total_units_returned,
        ROUND(SUM(return_value), 2)             AS total_return_value
    FROM {{ ref('stg_returns') }}
    GROUP BY salesperson_name
)

SELECT
    s.salesperson_name,
    s.total_transactions,
    s.active_days,
    s.total_units_sold,
    COALESCE(r.total_returns_processed, 0)      AS total_returns_processed,
    COALESCE(r.total_units_returned, 0)         AS total_units_returned,
    s.total_revenue,
    COALESCE(r.total_return_value, 0)           AS total_return_value,
    s.total_discounts_given,
    s.avg_transaction_value,
    s.mpesa_revenue,
    s.bank_revenue,
    s.first_sale_date,
    s.last_sale_date

FROM sales_agg s
LEFT JOIN returns_agg r ON s.salesperson_name = r.salesperson_name
ORDER BY s.total_revenue DESC
