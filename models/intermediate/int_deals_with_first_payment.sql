{{ config(materialized='view') }}

with deals as (
    select * from {{ ref('stg_hubspot__deals') }}
),

payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

first_payment as (
    select
        customer_email,
        min(created_at) as first_payment_at
    from payments
    where customer_email is not null
    group by 1
),

joined as (
    select
        deals.deal_id,
        deals.deal_name,
        deals.deal_owner,
        deals.amount,
        deals.close_date,
        deals.stage,
        deals.customer_email,
        first_payment.first_payment_at
    from deals
    left join first_payment
        on deals.customer_email = first_payment.customer_email
)

select * from joined
