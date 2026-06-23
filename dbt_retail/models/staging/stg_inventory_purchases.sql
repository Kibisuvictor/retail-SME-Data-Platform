{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned inventory purchase records. Source columns match actual Google Form headers.'
  )
}}

/*
  Source column mapping:
    "Date of Purchase"          → Date_of_Purchase
    "Product Purchased"         → Product_Purchased
    "Units Purchased"           → Units_Purchased
    "Unit Cost (KES)"           → Unit_Cost_KES
    "Supplier Name"             → Supplier_Name
    "Payment Method"            → Payment_Method
    "Notes/Comments (Optional)" → Notes_Comments
    "Business Unit"             → Business_Unit
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'inventory_purchases_raw') }}
    WHERE Date_of_Purchase IS NOT NULL
      AND TRIM(Date_of_Purchase) != ''
      AND Product_Purchased IS NOT NULL
),

cleaned AS (
    SELECT
        TO_HEX(MD5(
            CONCAT(
                COALESCE(TRIM(Date_of_Purchase), ''),   '|',
                COALESCE(TRIM(Product_Purchased), ''),  '|',
                COALESCE(TRIM(Units_Purchased), ''),    '|',
                COALESCE(Timestamp, '')
            )
        ))                                                              AS purchase_id,

        {{ parse_form_date('Date_of_Purchase') }}                       AS purchase_date,

        -- product_key must match slug in stg_products
        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product_Purchased), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                               AS product_key,

        {{ parse_form_int('Units_Purchased') }}                         AS units_purchased,
        {{ parse_form_number('Unit_Cost_KES') }}                        AS unit_cost,
        NULLIF(TRIM(COALESCE(Supplier_Name, '')), '')                   AS supplier_name,
        TRIM(Payment_Method)                                            AS payment_method,
        NULLIF(TRIM(COALESCE(Notes_Comments, '')), '')                  AS notes,

        -- Business unit (branch/division) that received this stock.
        NULLIF(TRIM(COALESCE(Business_Unit, '')), '')                   AS unit,

        {{ parse_form_timestamp('Timestamp') }}                         AS submitted_at

    FROM source
    WHERE {{ parse_form_int('Units_Purchased') }} > 0
      AND {{ parse_form_number('Unit_Cost_KES') }} > 0
      AND {{ parse_form_date('Date_of_Purchase') }} IS NOT NULL
)

SELECT
    purchase_id,
    purchase_date,
    product_key,
    units_purchased,
    unit_cost,
    ROUND(units_purchased * unit_cost, 2)   AS total_cost,
    supplier_name,
    payment_method,
    unit,
    notes,
    submitted_at
FROM cleaned
