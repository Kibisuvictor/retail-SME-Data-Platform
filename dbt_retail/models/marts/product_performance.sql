{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Per-variant, per-month sales, revenue, and ACCURATE profit using actual cost price per product.'
  )
}}

/*
  Grain: one row per (month, product_key) for every active product, for every
  month with any sales/returns activity across the catalog — plus the current
  calendar month, always, even before any activity happens in it. This lets
  Looker Studio default a date filter to "This month" instead of showing
  all-time cumulative totals.

  Profit uses the product's own cost_price from stg_products (entered by the
  owner in the Product Master Form) rather than the approximate COGS from
  inventory purchases. This gives exact margin per variant.

  Formula: gross_profit = (unit_price - cost_price) × units_sold
*/

WITH sales_agg AS (
    SELECT
        product_key,
        DATE_TRUNC(sale_date, MONTH)            AS month,
        COUNT(*)                                AS total_transactions,
        SUM(units_sold)                         AS total_units_sold,
        ROUND(SUM(net_amount), 2)               AS total_revenue,
        ROUND(SUM(discount_amount), 2)          AS total_discounts,
        ROUND(AVG(unit_price), 2)               AS avg_selling_price,
        MIN(sale_date)                          AS first_sale_date,
        MAX(sale_date)                          AS last_sale_date
    FROM {{ ref('stg_sales') }}
    GROUP BY product_key, DATE_TRUNC(sale_date, MONTH)
),

returns_agg AS (
    SELECT
        product_key,
        DATE_TRUNC(return_date, MONTH)          AS month,
        SUM(units_returned)                     AS total_units_returned,
        ROUND(SUM(return_value), 2)             AS total_return_value
    FROM {{ ref('stg_returns') }}
    GROUP BY product_key, DATE_TRUNC(return_date, MONTH)
),

-- Accurate profit per transaction using actual cost price
profit_calc AS (
    SELECT
        s.product_key,
        DATE_TRUNC(s.sale_date, MONTH)          AS month,
        ROUND(
            SUM(
                s.units_sold
                * GREATEST(s.unit_price - COALESCE(p.cost_price, 0), 0)
            ), 2
        )                                       AS total_gross_profit,
        ROUND(
            SUM(s.units_sold * COALESCE(p.cost_price, 0)), 2
        )                                       AS total_cogs
    FROM {{ ref('stg_sales') }} s
    LEFT JOIN {{ ref('stg_products') }} p ON s.product_key = p.product_key
    GROUP BY s.product_key, DATE_TRUNC(s.sale_date, MONTH)
),

-- Every month with any activity, plus the current month, so the catalog
-- always has a (possibly all-zero) row set for "this month".
all_months AS (
    SELECT month FROM sales_agg
    UNION DISTINCT
    SELECT month FROM returns_agg
    UNION DISTINCT
    SELECT DATE_TRUNC(CURRENT_DATE(), MONTH)
),

product_months AS (
    SELECT p.product_key, m.month
    FROM {{ ref('stg_products') }} p
    CROSS JOIN all_months m
    WHERE p.is_active = TRUE
)

SELECT
    pm.month,
    p.product_key,
    p.product_name,
    p.product_family,
    p.product_variant,
    p.category,
    p.unit_of_measure,
    p.selling_price                                     AS current_selling_price,
    p.cost_price                                        AS current_cost_price,
    p.unit_margin_kes                                   AS current_unit_margin_kes,
    p.unit_margin_pct                                   AS current_unit_margin_pct,
    p.reorder_level,

    -- Sales metrics
    COALESCE(s.total_transactions, 0)                   AS total_transactions,
    COALESCE(s.total_units_sold, 0)                     AS total_units_sold,
    COALESCE(r.total_units_returned, 0)                 AS total_units_returned,
    COALESCE(s.total_revenue, 0)                        AS total_revenue,
    COALESCE(r.total_return_value, 0)                   AS total_return_value,
    COALESCE(s.total_discounts, 0)                      AS total_discounts,
    COALESCE(s.avg_selling_price, 0)                    AS avg_selling_price,
    s.first_sale_date,
    s.last_sale_date,

    -- Accurate profit (cost price × units sold)
    COALESCE(pc.total_cogs, 0)                          AS total_cogs,
    ROUND(
        COALESCE(pc.total_gross_profit, 0)
        - COALESCE(r.total_return_value, 0),
        2
    )                                                   AS total_gross_profit,

    -- Gross margin %
    CASE
        WHEN COALESCE(s.total_revenue, 0) > 0
        THEN ROUND(
            (
                COALESCE(pc.total_gross_profit, 0)
                - COALESCE(r.total_return_value, 0)
            ) / s.total_revenue * 100, 1
        )
        ELSE NULL
    END                                                 AS gross_margin_pct

FROM product_months pm
JOIN {{ ref('stg_products') }} p       ON pm.product_key = p.product_key
LEFT JOIN sales_agg   s  ON pm.product_key = s.product_key AND pm.month = s.month
LEFT JOIN returns_agg r  ON pm.product_key = r.product_key AND pm.month = r.month
LEFT JOIN profit_calc pc ON pm.product_key = pc.product_key AND pm.month = pc.month
ORDER BY pm.month DESC, total_revenue DESC
