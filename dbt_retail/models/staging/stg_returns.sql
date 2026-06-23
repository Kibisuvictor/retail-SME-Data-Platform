{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned return transactions. Source columns match actual Google Form headers.'
  )
}}

/*
  Source column mapping:
    "Date of Return"                                        → Date_of_Return
    "Salesperson Name"                                      → Salesperson_Name
    "Product Returned (Select Item)"                        → Product_Returned
    "Units Returned (Must be greater than 0)"               → Units_Returned
    "Original Unit Price (KES) - What was the item sold for?" → Original_Unit_Price_KES
    "Reason for Return"                                     → Reason_for_Return
    "Requested Refund Method"                               → Requested_Refund_Method
    "Customer Phone Number (Optional)"                      → Customer_Phone_Number
    "Notes and Further Explanation (Optional)"              → Notes
    "Business Unit"                                         → Business_Unit
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'returns_raw') }}
    WHERE Date_of_Return IS NOT NULL
      AND TRIM(Date_of_Return) != ''
      AND Product_Returned IS NOT NULL
      AND TRIM(Product_Returned) != ''
),

cleaned AS (
    SELECT
        TO_HEX(MD5(
            CONCAT(
                COALESCE(TRIM(Date_of_Return), ''),         '|',
                COALESCE(TRIM(Salesperson_Name), ''),       '|',
                COALESCE(TRIM(Product_Returned), ''),       '|',
                COALESCE(TRIM(Units_Returned), ''),         '|',
                COALESCE(Timestamp, '')
            )
        ))                                                          AS return_id,

        {{ parse_form_date('Date_of_Return') }}                     AS return_date,
        UPPER(TRIM(Salesperson_Name))                               AS salesperson_name,

        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product_Returned), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                           AS product_key,

        {{ parse_form_int('Units_Returned') }}                      AS units_returned,

        COALESCE(
            {{ parse_form_number('Original_Unit_Price_KES') }}, 0
        )                                                           AS original_unit_price,

        ROUND(
            {{ parse_form_int('Units_Returned') }}
            * COALESCE({{ parse_form_number('Original_Unit_Price_KES') }}, 0),
            2
        )                                                           AS return_value,

        TRIM(Reason_for_Return)                                     AS return_reason,
        TRIM(Requested_Refund_Method)                               AS refund_method,

        CASE
            WHEN REGEXP_CONTAINS(
                TRIM(COALESCE(Customer_Phone_Number, '')),
                r'^(07|01)[0-9]{8}$'
            )
            THEN TRIM(Customer_Phone_Number)
            ELSE NULL
        END                                                         AS customer_phone,

        -- Business unit (branch/division) that processed this return.
        NULLIF(TRIM(COALESCE(Business_Unit, '')), '')               AS unit,

        NULLIF(TRIM(COALESCE(Notes, '')), '')                       AS notes,
        {{ parse_form_timestamp('Timestamp') }}                     AS submitted_at

    FROM source
    WHERE {{ parse_form_int('Units_Returned') }} > 0
      AND {{ parse_form_date('Date_of_Return') }} IS NOT NULL
)

SELECT * FROM cleaned
