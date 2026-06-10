-- tests/assert_no_future_return_dates.sql
-- Fails if any return has a date in the future.
-- Usually a data entry error in the Google Form.

SELECT
    return_id,
    return_date,
    salesperson_name,
    product_key
FROM {{ ref('stg_returns') }}
WHERE return_date > CURRENT_DATE()
