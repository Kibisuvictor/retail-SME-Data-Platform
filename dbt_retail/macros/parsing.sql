-- Robust parsers for Google Forms / Sheets raw values.

-- Sheet locale is US: dates arrive as MM/DD/YYYY, so MM/DD is tried first
-- and wins on ambiguous values like 05/04/2025 (= May 4).
{% macro parse_form_date(col) %}
COALESCE(
    SAFE_CAST(TRIM({{ col }}) AS DATE),
    SAFE.PARSE_DATE('%m/%d/%Y', TRIM({{ col }})),
    SAFE.PARSE_DATE('%d/%m/%Y', TRIM({{ col }})),
    SAFE_CAST(SAFE_CAST(TRIM({{ col }}) AS TIMESTAMP) AS DATE),
    SAFE_CAST(SAFE.PARSE_TIMESTAMP('%m/%d/%Y %H:%M:%S', TRIM({{ col }})) AS DATE),
    SAFE_CAST(SAFE.PARSE_TIMESTAMP('%d/%m/%Y %H:%M:%S', TRIM({{ col }})) AS DATE)
)
{% endmacro %}

-- Forms auto-Timestamp column, same US-first ordering.
{% macro parse_form_timestamp(col) %}
COALESCE(
    SAFE_CAST(TRIM({{ col }}) AS TIMESTAMP),
    SAFE.PARSE_TIMESTAMP('%m/%d/%Y %H:%M:%S', TRIM({{ col }})),
    SAFE.PARSE_TIMESTAMP('%d/%m/%Y %H:%M:%S', TRIM({{ col }}))
)
{% endmacro %}

-- Numbers may arrive formatted: "1,200", "KES 280", "280.00".
{% macro parse_form_number(col) %}
SAFE_CAST(
    NULLIF(REGEXP_REPLACE(COALESCE({{ col }}, ''), r'[^0-9.\-]', ''), '')
    AS NUMERIC
)
{% endmacro %}

{% macro parse_form_int(col) %}
SAFE_CAST({{ parse_form_number(col) }} AS INT64)
{% endmacro %}