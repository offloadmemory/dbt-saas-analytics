{{ config(materialized='table') }}

with deals_enriched as (
    select * from {{ ref('int_deals_with_first_payment') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

won as (
    select * from deals_enriched where stage = 'Closed-Won'
),

final as (
    select
        won.deal_id,
        won.deal_name,
        won.deal_owner,
        won.amount,
        won.close_date,
        won.customer_email,
        customers.customer_id,
        won.first_payment_at,
        case
            when won.first_payment_at is not null and won.close_date is not null
                then date_diff('day', won.first_payment_at::date, won.close_date)
        end as days_to_first_payment
    from won
    left join customers
        on won.customer_email = customers.customer_email
)

select * from final
