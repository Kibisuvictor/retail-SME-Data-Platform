{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-product sales, revenue, and estimated profit. Returns from dedicated Returns Form.'
  )
}}

WITH latest_cost AS (
    SELECT
        product_key,
        ARRAY_AGG(unit_cost  ORDER BY purchase_date DESC LIMIT 1)[OFFSET(0)] AS latest_cost_price,
        ARRAY_AGG(purchase_date ORDER BY purchase_date DESC LIMIT 1)[OFFSET(0)] AS last_restocked_date
    FROM {{ ref('stg_inventory_purchases') }}
    GROUP BY product_key
),

sales_agg AS (
    SELECT
        product_key,
        COUNT(*)                                AS total_transactions,
        SUM(units_sold)                         AS total_units_sold,
        ROUND(SUM(net_amount), 2)               AS total_revenue,
        ROUND(SUM(discount_amount), 2)          AS total_discounts,
        ROUND(AVG(unit_price), 2)               AS avg_selling_price,
        MIN(sale_date)                          AS first_sale_date,
        MAX(sale_date)                          AS last_sale_date
    FROM {{ ref('stg_sales') }}
    GROUP BY product_key
),

returns_agg AS (
    SELECT
        product_key,
        SUM(units_returned)                     AS total_units_returned,
        ROUND(SUM(return_value), 2)             AS total_return_value
    FROM {{ ref('stg_returns') }}
    GROUP BY product_key
)

SELECT
    p.product_key,
    p.product_name,
    p.category,
    p.unit_of_measure,
    p.selling_price                                     AS current_selling_price,
    p.reorder_level,

    COALESCE(s.total_transactions, 0)                   AS total_transactions,
    COALESCE(s.total_units_sold, 0)                     AS total_units_sold,
    COALESCE(r.total_units_returned, 0)                 AS total_units_returned,
    COALESCE(s.total_revenue, 0)                        AS total_revenue,
    COALESCE(r.total_return_value, 0)                   AS total_return_value,
    COALESCE(s.total_discounts, 0)                      AS total_discounts,
    COALESCE(s.avg_selling_price, 0)                    AS avg_selling_price,
    s.first_sale_date,
    s.last_sale_date,

    COALESCE(lc.latest_cost_price, 0)                   AS latest_cost_price,
    lc.last_restocked_date,

    -- Estimated gross profit (net of returns)
    ROUND(
        COALESCE(s.total_revenue, 0)
        - COALESCE(r.total_return_value, 0)
        - (COALESCE(s.total_units_sold, 0) * COALESCE(lc.latest_cost_price, 0)),
        2
    )                                                   AS estimated_gross_profit,

    -- Gross margin %
    CASE
        WHEN COALESCE(s.total_revenue, 0) > 0
        THEN ROUND(
            (
                COALESCE(s.total_revenue, 0)
                - COALESCE(r.total_return_value, 0)
                - (COALESCE(s.total_units_sold, 0) * COALESCE(lc.latest_cost_price, 0))
            ) / s.total_revenue * 100,
            1
        )
        ELSE 0
    END                                                 AS gross_margin_pct

FROM {{ ref('stg_products') }} p
LEFT JOIN sales_agg   s  ON p.product_key = s.product_key
LEFT JOIN returns_agg r  ON p.product_key = r.product_key
LEFT JOIN latest_cost lc ON p.product_key = lc.product_key
WHERE p.is_active = TRUE
ORDER BY total_revenue DESC
