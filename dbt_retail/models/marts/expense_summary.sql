{{
  config(
    materialized = 'table',
    dataset      = 'retail_marts',
    description  = 'Daily expense totals by category.'
  )
}}

SELECT
    expense_date,
    expense_category,

    COUNT(*)                                                AS transaction_count,
    ROUND(SUM(amount), 2)                                   AS total_amount,

    ROUND(SUM(CASE WHEN paid_via = 'M-Pesa' THEN amount ELSE 0 END), 2) AS mpesa_amount,
    ROUND(SUM(CASE WHEN paid_via = 'Bank'   THEN amount ELSE 0 END), 2) AS bank_amount,

    DATE_TRUNC(expense_date, MONTH)                         AS month_start,
    DATE_TRUNC(expense_date, WEEK(MONDAY))                  AS week_start

FROM {{ ref('stg_expenses') }}
GROUP BY expense_date, expense_category
ORDER BY expense_date DESC, total_amount DESC
