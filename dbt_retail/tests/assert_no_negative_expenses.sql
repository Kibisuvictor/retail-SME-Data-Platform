-- tests/assert_no_negative_expenses.sql
SELECT expense_id, expense_date, expense_category, amount
FROM {{ ref('stg_expenses') }}
WHERE amount <= 0
