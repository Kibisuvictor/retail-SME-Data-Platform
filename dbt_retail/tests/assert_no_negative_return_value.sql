-- tests/assert_no_negative_return_value.sql
-- Fails if any return has zero or negative return_value.
-- Caused by original_unit_price being 0 or missing.

SELECT
    return_id,
    return_date,
    product_key,
    units_returned,
    original_unit_price,
    return_value
FROM {{ ref('stg_returns') }}
WHERE return_value <= 0
