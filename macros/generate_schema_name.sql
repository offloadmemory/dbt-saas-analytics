{#
  Override dbt's default `generate_schema_name` so per-layer `+schema:` config
  (`staging`, `intermediate`, `marts`, `seeds`) resolves to the layer name
  verbatim instead of being concatenated to the profile's default schema.

  Without this, dbt-databricks ships seeds to `<profile_schema>_seeds`
  (`default_seeds`) and models to `<profile_schema>_<layer>` (`default_staging`),
  which doesn't match what `models/staging/_sources.yml` declares (i.e. plain
  `seeds`) and produces an ugly catalog layout.

  This is the standard dbt pattern for clean per-layer schema routing; see
  https://docs.getdbt.com/docs/build/custom-schemas#how-do-i-use-the-same-schema-for-all-my-models
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
