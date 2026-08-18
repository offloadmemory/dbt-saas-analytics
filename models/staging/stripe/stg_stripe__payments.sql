{{ config(materialized='view') }}

with source as (
    select * from {{ source('stripe', 'stripe_payments') }}
),

renamed as (
    select
        payment_id,
        customer_id,
        -- DuckDB coerces an unquoted CSV "null" to the literal string 'null',
        -- not SQL NULL. Treat that as missing so downstream joins don't
        -- fabricate a fake customer.
        case
            when lower(trim(customer_email)) = 'null' then null
            else lower(trim(customer_email))
        end as customer_email,
        cast(amount as numeric(14, 2)) as amount,
        currency,
        cast(created_at as timestamp) as created_at
    from source
)

select * from renamed
