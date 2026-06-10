{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-customer purchase summary with masked phone numbers.'
  )
}}

/*
  Privacy: phone numbers are masked before surfacing in dashboards.
  Pattern: 0712345678 → 07XX****78
  Full numbers live only in staging.stg_sales (not directly queryable via Looker Studio).
*/

SELECT
    -- Masked phone: first 4 + **** + last 2 digits
    CONCAT(
        SUBSTR(customer_phone, 1, 4),
        '****',
        SUBSTR(customer_phone, LENGTH(customer_phone) - 1, 2)
    )                                                   AS customer_phone_masked,

    COUNT(*)                                            AS total_transactions,
    COUNT(DISTINCT sale_date)                           AS purchase_days,

    ROUND(SUM(net_amount), 2)                           AS total_spent,
    ROUND(AVG(net_amount), 2)                           AS avg_transaction_value,
    ROUND(MAX(net_amount), 2)                           AS largest_transaction,
    SUM(units_sold)                                     AS total_units_purchased,

    MIN(sale_date)                                      AS first_purchase_date,
    MAX(sale_date)                                      AS last_purchase_date,

    DATE_DIFF(CURRENT_DATE(), MAX(sale_date), DAY)      AS days_since_last_purchase,

    CASE
        WHEN SUM(net_amount) >= 10000 THEN 'VIP'
        WHEN SUM(net_amount) >= 3000  THEN 'Regular'
        ELSE 'Occasional'
    END                                                 AS customer_tier,

    CASE
        WHEN COUNT(DISTINCT sale_date) > 1 THEN TRUE
        ELSE FALSE
    END                                                 AS is_repeat_customer

FROM {{ ref('stg_sales') }}
WHERE customer_phone IS NOT NULL
GROUP BY customer_phone
ORDER BY total_spent DESC
