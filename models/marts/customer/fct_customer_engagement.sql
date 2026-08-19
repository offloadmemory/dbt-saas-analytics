{{ config(materialized='table') }}

-- Customer engagement fact: one row per customer with engagement signals
-- across all three source systems. Useful for the customer support / success
-- VP who needs to know "who is engaging with us, how much, and when."
--
-- Without a dedicated support / ticketing source in this project, this
-- mart is a proxy built from the data we have: deal touchpoints, payment
-- activity, and order history. When a real support source is added
-- (e.g. Zendesk, Intercom), extend this mart with ticket-level metrics.

with customers as (
    select * from {{ ref('dim_customers') }}
),

deals as (
    select
        customer_email,
        count(*) as deal_count,
        sum(amount) as total_deal_amount,
        max(close_date) as last_deal_date
    from {{ ref('stg_hubspot__deals') }}
    where customer_email is not null
    group by 1
),

payments as (
    select
        customer_email,
        count(*) as payment_count,
        sum(amount) as total_payment_amount,
        max(created_at) as last_payment_at
    from {{ ref('stg_stripe__payments') }}
    where customer_email is not null
    group by 1
),

orders as (
    select
        customer_email,
        count(*) as order_count,
        sum(total_amount) as total_order_amount,
        max(order_date) as last_order_date
    from {{ ref('stg_zoho__orders') }}
    where customer_email is not null
    group by 1
),

final as (
    select
        customers.customer_id,
        customers.customer_email,
        coalesce(deals.deal_count, 0) as deal_count,
        coalesce(deals.total_deal_amount, 0) as total_deal_amount,
        deals.last_deal_date,
        coalesce(payments.payment_count, 0) as payment_count,
        coalesce(payments.total_payment_amount, 0) as total_payment_amount,
        payments.last_payment_at,
        coalesce(orders.order_count, 0) as order_count,
        coalesce(orders.total_order_amount, 0) as total_order_amount,
        orders.last_order_date,
        -- "Last engagement" = most recent of the three signals. Useful for
        -- "who hasn't engaged in 90 days" queries.
        greatest(
            coalesce(deals.last_deal_date, timestamp '1900-01-01 00:00:00'),
            coalesce(payments.last_payment_at, timestamp '1900-01-01 00:00:00'),
            coalesce(orders.last_order_date, timestamp '1900-01-01 00:00:00')
        ) as last_engagement_at
    from customers
    left join deals on customers.customer_email = deals.customer_email
    left join payments on customers.customer_email = payments.customer_email
    left join orders on customers.customer_email = orders.customer_email
)

select * from final
