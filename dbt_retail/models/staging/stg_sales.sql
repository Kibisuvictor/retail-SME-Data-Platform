{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned sales transactions. Source columns match actual Google Form headers.'
  )
}}

/*
  Source column mapping (Google Form header → BigQuery column name):
    "Date"                    → Date
    "Salesperson Name"        → Salesperson_Name
    "Product"                 → Product
    "Units Sold"              → Units_Sold
    "Unit Price (KES)"        → Unit_Price_KES
    "Discount Amount (KES)"   → Discount_Amount_KES
    "Payment Method"          → Payment_Method
    "Customer Phone Number"   → Customer_Phone_Number
    "Customer Type"           → Customer_Type
    "Business Unit"           → Business_Unit
    "Notes"                   → Notes

  Note: "Return" column removed — returns now handled by dedicated Returns Form.
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'sales_raw') }}
    WHERE Date IS NOT NULL
      AND TRIM(Date) != ''
      AND Product IS NOT NULL
      AND TRIM(Product) != ''
),

cleaned AS (
    SELECT
        TO_HEX(MD5(
            CONCAT(
                COALESCE(TRIM(Date), ''),              '|',
                COALESCE(TRIM(Salesperson_Name), ''),  '|',
                COALESCE(TRIM(Product), ''),           '|',
                COALESCE(Timestamp, '')
            )
        ))                                                          AS sale_id,

        {{ parse_form_date('Date') }}                               AS sale_date,
        UPPER(TRIM(Salesperson_Name))                               AS salesperson_name,

        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                           AS product_key,

        {{ parse_form_int('Units_Sold') }}                          AS units_sold,
        COALESCE({{ parse_form_number('Unit_Price_KES') }}, 0)      AS unit_price,
        COALESCE({{ parse_form_number('Discount_Amount_KES') }}, 0) AS discount_amount,
        TRIM(Payment_Method)                                        AS payment_method,

        -- Phone validation: null if not a valid Kenyan mobile number
        CASE
            WHEN REGEXP_CONTAINS(
                TRIM(COALESCE(Customer_Phone_Number, '')),
                r'^(07|01)[0-9]{8}$'
            )
            THEN TRIM(Customer_Phone_Number)
            ELSE NULL
        END                                                         AS customer_phone,

        TRIM(COALESCE(Customer_Type, ''))                           AS customer_type,

        -- Business unit (branch/division). NULL for rows entered before
        -- this field existed — accepted_values test ignores NULLs.
        NULLIF(TRIM(COALESCE(Business_Unit, '')), '')               AS unit,

        NULLIF(TRIM(COALESCE(Notes, '')), '')                       AS notes,
        {{ parse_form_timestamp('Timestamp') }}                     AS submitted_at

    FROM source
    WHERE {{ parse_form_int('Units_Sold') }} > 0
      AND {{ parse_form_date('Date') }} IS NOT NULL
),

with_amounts AS (
    SELECT
        *,
        ROUND(units_sold * unit_price, 2)                           AS gross_amount,
        ROUND((units_sold * unit_price) - discount_amount, 2)       AS net_amount
    FROM cleaned
)

SELECT * FROM with_amounts
