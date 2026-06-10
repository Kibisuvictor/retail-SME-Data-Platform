-- tests/assert_no_future_sale_dates.sql
SELECT sale_id, sale_date, salesperson_name, product_key
FROM {{ ref('stg_sales') }}
WHERE sale_date > CURRENT_DATE()
