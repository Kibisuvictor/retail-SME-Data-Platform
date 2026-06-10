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

        SAFE_CAST(Date_of_Purchase AS DATE)                             AS purchase_date,

        -- product_key must match slug in stg_products
        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product_Purchased), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                               AS product_key,

        SAFE_CAST(Units_Purchased AS INT64)                             AS units_purchased,
        SAFE_CAST(Unit_Cost_KES AS NUMERIC)                             AS unit_cost,
        NULLIF(TRIM(COALESCE(Supplier_Name, '')), '')                   AS supplier_name,
        TRIM(Payment_Method)                                            AS payment_method,
        NULLIF(TRIM(COALESCE(Notes_Comments, '')), '')                  AS notes,
        SAFE_CAST(Timestamp AS TIMESTAMP)                               AS submitted_at

    FROM source
    WHERE SAFE_CAST(Units_Purchased AS INT64) > 0
      AND SAFE_CAST(Unit_Cost_KES AS NUMERIC) > 0
      AND SAFE_CAST(Date_of_Purchase AS DATE) IS NOT NULL
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
    notes,
    submitted_at
FROM cleaned
