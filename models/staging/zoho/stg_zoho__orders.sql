{{ config(materialized='view') }}

with source as (
    select * from {{ source('zoho', 'zoho_orders') }}
),

renamed as (
    select
        cast(order_id as integer) as order_id,
        customer_name,
        lower(trim(customer_email)) as customer_email,
        product_name,
        cast(quantity as integer) as quantity,
        cast(unit_price as numeric(14, 2)) as unit_price,
        cast(total_amount as numeric(14, 2)) as total_amount,
        cast(order_date as date) as order_date
    from source
)

select * from renamed
