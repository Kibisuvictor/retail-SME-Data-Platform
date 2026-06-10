{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned expense records. Source columns match actual Google Form headers.'
  )
}}

/*
  Source column mapping:
    "Date of Expense"   → Date_of_Expense
    "Expense Category"  → Expense_Category
    "Amount (KES)"      → Amount_KES
    "Description"       → Description
    "Paid Via"          → Paid_Via
    "Recorded By"       → Recorded_By
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'expenses_raw') }}
    WHERE Date_of_Expense IS NOT NULL
      AND TRIM(Date_of_Expense) != ''
      AND Expense_Category IS NOT NULL
),

cleaned AS (
    SELECT
        TO_HEX(MD5(
            CONCAT(
                COALESCE(TRIM(Date_of_Expense), ''),   '|',
                COALESCE(TRIM(Expense_Category), ''),  '|',
                COALESCE(TRIM(Amount_KES), ''),        '|',
                COALESCE(Timestamp, '')
            )
        ))                                              AS expense_id,

        SAFE_CAST(Date_of_Expense AS DATE)              AS expense_date,
        TRIM(Expense_Category)                          AS expense_category,
        SAFE_CAST(Amount_KES AS NUMERIC)                AS amount,
        NULLIF(TRIM(COALESCE(Description, '')), '')     AS description,
        TRIM(Paid_Via)                                  AS paid_via,
        UPPER(TRIM(Recorded_By))                        AS recorded_by,
        SAFE_CAST(Timestamp AS TIMESTAMP)               AS submitted_at

    FROM source
    WHERE SAFE_CAST(Amount_KES AS NUMERIC) > 0
      AND SAFE_CAST(Date_of_Expense AS DATE) IS NOT NULL
)

SELECT * FROM cleaned
