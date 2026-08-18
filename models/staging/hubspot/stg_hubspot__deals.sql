{{ config(materialized='view') }}

with source as (
    select * from {{ source('hubspot', 'hubspot_deals') }}
),

renamed as (
    select
        cast(deal_id as integer) as deal_id,
        deal_name,
        deal_owner,
        cast(amount as numeric(14, 2)) as amount,
        cast(close_date as date) as close_date,
        stage,
        lower(trim(customer_email)) as customer_email
    from source
)

select * from renamed
