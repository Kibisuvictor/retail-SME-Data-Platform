{{
  config(
    materialized = 'table',
    dataset      = 'retail_staging',
    description  = 'Cleaned product master with cost price per variant. One row per active product.'
  )
}}

/*
  Source column mapping:
    "Product Name (Must be exact...)"    → Product_Name
    "Category"                           → Category
    "Unit of Measure (UoM)"              → Unit_of_Measure
    "Current Selling Price (KES)"        → Current_Selling_Price
    "Cost Price (KES)"                   → Cost_Price_KES  ← NEW
    "Reorder Level (units)..."           → Reorder_Level
    "Is this product currently active?"  → Is_Active

  product_key is a slug of the full variant name, e.g.:
    "Locks - Moment"  →  "locks_moment"
    "Grass - 10mm"    →  "grass_10mm"
  This is the join key used across all staging and mart models.
*/

WITH source AS (
    SELECT * FROM {{ source('retail_raw', 'products_raw') }}
    WHERE Product_Name IS NOT NULL
      AND TRIM(Product_Name) != ''
),

cleaned AS (
    SELECT
        -- product_key: slug of full variant name
        LOWER(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(Product_Name), r'[^a-zA-Z0-9\s]', ''),
                r'\s+', '_'
            )
        )                                                       AS product_key,

        TRIM(Product_Name)                                      AS product_name,

        -- Extract family from "Family - Variant" naming convention
        -- e.g. "Locks - Moment" → family = "Locks"
        CASE
            WHEN STRPOS(TRIM(Product_Name), ' - ') > 0
            THEN TRIM(SPLIT(TRIM(Product_Name), ' - ')[OFFSET(0)])
            ELSE TRIM(Product_Name)
        END                                                     AS product_family,

        -- Extract variant from "Family - Variant" naming convention
        CASE
            WHEN STRPOS(TRIM(Product_Name), ' - ') > 0
            THEN TRIM(SPLIT(TRIM(Product_Name), ' - ')[OFFSET(1)])
            ELSE NULL
        END                                                     AS product_variant,

        TRIM(Category)                                          AS category,
        TRIM(Unit_of_Measure)                                   AS unit_of_measure,
        {{ parse_form_number('Current_Selling_Price') }}        AS selling_price,
        {{ parse_form_number('Cost_Price_KES') }}               AS cost_price,

        COALESCE(
            {{ parse_form_int('Reorder_Level') }}, 5
        )                                                       AS reorder_level,

        CASE
            WHEN LOWER(TRIM(Is_Active)) IN ('yes', 'true', '1') THEN TRUE
            ELSE FALSE
        END                                                     AS is_active,

        {{ parse_form_timestamp('Timestamp') }}                 AS submitted_at

    FROM source
    WHERE {{ parse_form_number('Current_Selling_Price') }} > 0
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
    product_family,
    product_variant,
    category,
    unit_of_measure,
    selling_price,
    cost_price,
    -- Derived margin fields — useful in Looker Studio directly
    ROUND(selling_price - COALESCE(cost_price, 0), 2)              AS unit_margin_kes,
    CASE
        WHEN selling_price > 0 AND cost_price IS NOT NULL
        THEN ROUND((selling_price - cost_price) / selling_price * 100, 1)
        ELSE NULL
    END                                                             AS unit_margin_pct,
    reorder_level,
    is_active,
    submitted_at
FROM deduped
WHERE rn = 1
