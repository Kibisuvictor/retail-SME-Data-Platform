{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Current stock per product derived from all inventory movements. Returns come from the dedicated Returns Form.'
  )
}}

/*
  Stock on hand = total purchased - total sold + total returned

  Returns are sourced exclusively from stg_returns (the dedicated Returns Form).
  stg_sales contains only sales — the old is_return flag was
  the old approach before the dedicated form existed. Any legacy return-flagged
  sales are excluded to avoid double-counting.
*/

WITH purchases AS (
    SELECT
        product_key,
        SUM(units_purchased)    AS total_purchased,
        SUM(total_cost)         AS total_purchase_cost,
        MAX(purchase_date)      AS last_purchase_date,
        ARRAY_AGG(
            unit_cost ORDER BY purchase_date DESC LIMIT 1
        )[OFFSET(0)]            AS latest_unit_cost
    FROM {{ ref('stg_inventory_purchases') }}
    GROUP BY product_key
),

sales AS (
    SELECT
        product_key,
        SUM(units_sold)     AS total_sold,
        SUM(net_amount)     AS total_revenue
    FROM {{ ref('stg_sales') }}
    GROUP BY product_key
),

-- Returns now come from the dedicated Returns Form only
returns AS (
    SELECT
        product_key,
        SUM(units_returned)     AS total_returned,
        SUM(return_value)       AS total_return_value
    FROM {{ ref('stg_returns') }}
    GROUP BY product_key
)

SELECT
    p.product_key,
    p.product_name,
    p.category,
    p.unit_of_measure,
    p.selling_price,
    p.reorder_level,

    COALESCE(pu.total_purchased, 0)         AS total_purchased,
    COALESCE(pu.total_purchase_cost, 0)     AS total_purchase_cost,
    pu.last_purchase_date,
    COALESCE(pu.latest_unit_cost, 0)        AS latest_unit_cost,

    COALESCE(s.total_sold, 0)               AS total_sold,
    COALESCE(r.total_returned, 0)           AS total_returned,
    COALESCE(s.total_revenue, 0)            AS total_revenue,
    COALESCE(r.total_return_value, 0)       AS total_return_value,

    -- Stock on hand: purchases - sales + returns
    COALESCE(pu.total_purchased, 0)
        - COALESCE(s.total_sold, 0)
        + COALESCE(r.total_returned, 0)     AS stock_on_hand,

    -- Inventory value at cost
    ROUND(
        (
            COALESCE(pu.total_purchased, 0)
            - COALESCE(s.total_sold, 0)
            + COALESCE(r.total_returned, 0)
        ) * COALESCE(pu.latest_unit_cost, 0),
        2
    )                                       AS inventory_value_at_cost,

    -- Inventory value at retail
    ROUND(
        (
            COALESCE(pu.total_purchased, 0)
            - COALESCE(s.total_sold, 0)
            + COALESCE(r.total_returned, 0)
        ) * p.selling_price,
        2
    )                                       AS inventory_value_at_retail,

    CASE
        WHEN (
            COALESCE(pu.total_purchased, 0)
            - COALESCE(s.total_sold, 0)
            + COALESCE(r.total_returned, 0)
        ) <= 0
            THEN 'Out of Stock'
        WHEN (
            COALESCE(pu.total_purchased, 0)
            - COALESCE(s.total_sold, 0)
            + COALESCE(r.total_returned, 0)
        ) <= p.reorder_level
            THEN 'Low Stock'
        ELSE 'In Stock'
    END                                     AS stock_status,

    CASE
        WHEN (
            COALESCE(pu.total_purchased, 0)
            - COALESCE(s.total_sold, 0)
            + COALESCE(r.total_returned, 0)
        ) <= p.reorder_level
            THEN TRUE
        ELSE FALSE
    END                                     AS needs_reorder

FROM {{ ref('stg_products') }} p
LEFT JOIN purchases pu ON p.product_key = pu.product_key
LEFT JOIN sales     s  ON p.product_key = s.product_key
LEFT JOIN returns   r  ON p.product_key = r.product_key
WHERE p.is_active = TRUE
ORDER BY p.category, p.product_name
