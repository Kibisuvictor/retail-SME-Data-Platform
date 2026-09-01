{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-salesperson, per-month performance. Returns processed from dedicated Returns Form.'
  )
}}

/*
  Grain: one row per (month, salesperson_name), for every month that
  salesperson had at least one sale or processed a return. There is no
  standing "all salespeople" dimension (unlike business units or products),
  so — unlike product_performance/unit_performance — this table does not
  force a zero row for the current month if nobody has sold anything yet.
*/

WITH sales_agg AS (
    SELECT
        salesperson_name,
        DATE_TRUNC(sale_date, MONTH)            AS month,
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
    GROUP BY salesperson_name, DATE_TRUNC(sale_date, MONTH)
),

returns_agg AS (
    SELECT
        salesperson_name,
        DATE_TRUNC(return_date, MONTH)          AS month,
        COUNT(*)                                AS total_returns_processed,
        SUM(units_returned)                     AS total_units_returned,
        ROUND(SUM(return_value), 2)             AS total_return_value
    FROM {{ ref('stg_returns') }}
    GROUP BY salesperson_name, DATE_TRUNC(return_date, MONTH)
),

all_keys AS (
    SELECT salesperson_name, month FROM sales_agg
    UNION DISTINCT
    SELECT salesperson_name, month FROM returns_agg
)

SELECT
    k.salesperson_name,
    k.month,
    COALESCE(s.total_transactions, 0)           AS total_transactions,
    COALESCE(s.active_days, 0)                  AS active_days,
    COALESCE(s.total_units_sold, 0)             AS total_units_sold,
    COALESCE(r.total_returns_processed, 0)      AS total_returns_processed,
    COALESCE(r.total_units_returned, 0)         AS total_units_returned,
    COALESCE(s.total_revenue, 0)                AS total_revenue,
    COALESCE(r.total_return_value, 0)           AS total_return_value,
    COALESCE(s.total_discounts_given, 0)        AS total_discounts_given,
    COALESCE(s.avg_transaction_value, 0)        AS avg_transaction_value,
    COALESCE(s.mpesa_revenue, 0)                AS mpesa_revenue,
    COALESCE(s.bank_revenue, 0)                 AS bank_revenue,
    s.first_sale_date,
    s.last_sale_date

FROM all_keys k
LEFT JOIN sales_agg   s ON k.salesperson_name = s.salesperson_name AND k.month = s.month
LEFT JOIN returns_agg r ON k.salesperson_name = r.salesperson_name AND k.month = r.month
ORDER BY k.month DESC, total_revenue DESC
