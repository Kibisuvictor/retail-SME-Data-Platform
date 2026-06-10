-- macros/utils.sql

{% macro generate_surrogate_key(column_names) %}
    TO_HEX(MD5(
        CONCAT(
            {% for col in column_names %}
                COALESCE(CAST({{ col }} AS STRING), '')
                {% if not loop.last %}, '|', {% endif %}
            {% endfor %}
        )
    ))
{% endmacro %}


{% macro safe_divide(numerator, denominator, default_value=0) %}
    CASE
        WHEN {{ denominator }} = 0 OR {{ denominator }} IS NULL
        THEN {{ default_value }}
        ELSE ROUND(SAFE_DIVIDE({{ numerator }}, {{ denominator }}), 4)
    END
{% endmacro %}


{% macro product_key_from_name(column_name) %}
    LOWER(
        REGEXP_REPLACE(
            REGEXP_REPLACE(TRIM({{ column_name }}), r'[^a-zA-Z0-9\s]', ''),
            r'\s+', '_'
        )
    )
{% endmacro %}
