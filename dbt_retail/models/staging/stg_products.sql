{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned product master. Source columns match actual Google Form headers.'
  )
}}

/*
  Source column mapping:
    "Product Name (Must be exact...)"          → Product_Name
    "Category"                                 → Category
    "Unit of Measure (UoM)"                    → Unit_of_Measure
    "Current Selling Price (KES)"              → Current_Selling_Price
    "Reorder Level (units) - Default is 5"     → Reorder_Level
    "Is this product currently active?"        → Is_Active
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'products_raw') }}
    WHERE Product_Name IS NOT NULL
      AND TRIM(Product_Name) != ''
),

cleaned AS (
    SELECT
        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product_Name), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                       AS product_key,

        TRIM(Product_Name)                                      AS product_name,
        TRIM(Category)                                          AS category,
        TRIM(Unit_of_Measure)                                   AS unit_of_measure,
        SAFE_CAST(Current_Selling_Price AS NUMERIC)             AS selling_price,

        COALESCE(
            SAFE_CAST(Reorder_Level AS INT64), 5
        )                                                       AS reorder_level,

        CASE
            WHEN LOWER(TRIM(Is_Active)) IN ('yes', 'true', '1') THEN TRUE
            ELSE FALSE
        END                                                     AS is_active,

        SAFE_CAST(Timestamp AS TIMESTAMP)                       AS submitted_at

    FROM source
    WHERE SAFE_CAST(Current_Selling_Price AS NUMERIC) IS NOT NULL
      AND SAFE_CAST(Current_Selling_Price AS NUMERIC) > 0
),

deduped AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY product_key
            ORDER BY submitted_at DESC NULLS LAST
        ) AS rn
    FROM cleaned
)

SELECT
    product_key,
    product_name,
    category,
    unit_of_measure,
    selling_price,
    reorder_level,
    is_active,
    submitted_at
FROM deduped
WHERE rn = 1
