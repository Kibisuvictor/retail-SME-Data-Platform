-- tests/assert_sale_price_above_cost.sql
-- Flags sales where unit price is below the latest cost — possible data entry error.
SELECT
    s.sale_id,
    s.sale_date,
    s.product_key,
    s.unit_price        AS sale_price,
    lc.latest_cost_price
FROM {{ ref('stg_sales') }} s
JOIN (
    SELECT
        product_key,
        ARRAY_AGG(unit_cost ORDER BY purchase_date DESC LIMIT 1)[OFFSET(0)] AS latest_cost_price
    FROM {{ ref('stg_inventory_purchases') }}
    GROUP BY product_key
) lc ON s.product_key = lc.product_key
WHERE s.unit_price < lc.latest_cost_price
