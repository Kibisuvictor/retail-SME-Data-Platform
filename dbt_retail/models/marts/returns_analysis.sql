{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Return trends by product, reason, refund method, and salesperson.'
  )
}}

/*
  This mart answers:
    - Which products get returned most?
    - Why are items being returned (defective vs wrong item vs change of mind)?
    - How are refunds being issued (M-Pesa, Bank, Store Credit, No Refund)?
    - Which salesperson processes the most returns?
    - Is the return rate increasing over time?
*/

WITH base AS (
    SELECT
        r.return_id,
        r.return_date,
        r.salesperson_name,
        r.product_key,
        p.product_name,
        p.category,
        r.units_returned,
        r.original_unit_price,
        r.return_value,
        r.return_reason,
        r.refund_method,
        r.customer_phone,
        r.notes,
        DATE_TRUNC(r.return_date, MONTH)        AS month_start,
        DATE_TRUNC(r.return_date, WEEK(MONDAY)) AS week_start
    FROM {{ ref('stg_returns') }} r
    LEFT JOIN {{ ref('stg_products') }} p ON r.product_key = p.product_key
),

-- Sales volume per product for return rate calculation
sales_volume AS (
    SELECT
        product_key,
        SUM(units_sold) AS total_units_sold
    FROM {{ ref('stg_sales') }}
    GROUP BY product_key
)

SELECT
    b.return_id,
    b.return_date,
    b.month_start,
    b.week_start,
    b.salesperson_name,
    b.product_key,
    b.product_name,
    b.category,
    b.units_returned,
    b.original_unit_price,
    b.return_value,
    b.return_reason,
    b.refund_method,
    b.customer_phone,
    b.notes,

    -- Return rate: what % of total units sold for this product were returned
    CASE
        WHEN COALESCE(sv.total_units_sold, 0) > 0
        THEN ROUND(
            b.units_returned / sv.total_units_sold * 100,
            2
        )
        ELSE NULL
    END                                         AS product_return_rate_pct

FROM base b
LEFT JOIN sales_volume sv ON b.product_key = sv.product_key
ORDER BY b.return_date DESC
