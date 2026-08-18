{{ config(materialized='table') }}

with deals as (
    select * from {{ ref('stg_hubspot__deals') }}
),

payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

orders as (
    select * from {{ ref('stg_zoho__orders') }}
),

deal_totals as (
    select
        customer_email,
        min(close_date) as first_deal_date,
        sum(amount) as total_deal_amount
    from deals
    where customer_email is not null
    group by 1
),

payment_totals as (
    select
        customer_email,
        min(created_at) as first_payment_date,
        sum(amount) as total_payment_amount
    from payments
    where customer_email is not null
    group by 1
),

order_totals as (
    select
        customer_email,
        min(order_date) as first_order_date,
        sum(total_amount) as total_order_amount
    from orders
    where customer_email is not null
    group by 1
),

-- Union of all customer emails seen anywhere. Inner side of the final left join.
all_emails as (
    select customer_email from deal_totals
    union
    select customer_email from payment_totals
    union
    select customer_email from order_totals
),

final as (
    select
        md5(lower(trim(all_emails.customer_email))) as customer_id,
        all_emails.customer_email,
        deal_totals.first_deal_date,
        payment_totals.first_payment_date,
        order_totals.first_order_date,
        coalesce(deal_totals.total_deal_amount, 0) as total_deal_amount,
        coalesce(payment_totals.total_payment_amount, 0) as total_payment_amount,
        coalesce(order_totals.total_order_amount, 0) as total_order_amount
    from all_emails
    left join deal_totals
        on all_emails.customer_email = deal_totals.customer_email
    left join payment_totals
        on all_emails.customer_email = payment_totals.customer_email
    left join order_totals
        on all_emails.customer_email = order_totals.customer_email
)

select * from final
