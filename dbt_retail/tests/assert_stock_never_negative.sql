-- tests/assert_stock_never_negative.sql
SELECT product_key, product_name, stock_on_hand
FROM {{ ref('inventory_position') }}
WHERE stock_on_hand < 0
