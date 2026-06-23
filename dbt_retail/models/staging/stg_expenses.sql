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
    "Recorded By"        → Recorded_By
    "Business Unit"      → Business_Unit
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

        {{ parse_form_date('Date_of_Expense') }}        AS expense_date,
        TRIM(Expense_Category)                          AS expense_category,
        {{ parse_form_number('Amount_KES') }}           AS amount,
        NULLIF(TRIM(COALESCE(Description, '')), '')     AS description,
        TRIM(Paid_Via)                                  AS paid_via,
        UPPER(TRIM(Recorded_By))                        AS recorded_by,

        -- Business unit (branch/division). NULL for rows predating this field
        -- — accepted_values test ignores NULLs, so historical data won't fail.
        NULLIF(TRIM(COALESCE(Business_Unit, '')), '')   AS unit,

        {{ parse_form_timestamp('Timestamp') }}         AS submitted_at

    FROM source
    WHERE {{ parse_form_number('Amount_KES') }} > 0
      AND {{ parse_form_date('Date_of_Expense') }} IS NOT NULL
)

SELECT * FROM cleaned
