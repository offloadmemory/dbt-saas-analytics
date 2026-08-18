{{ config(materialized='view') }}

with payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

orders as (
    select * from {{ ref('stg_zoho__orders') }}
),

-- One Zoho order per customer_email (the earliest). Customers can have
-- multiple orders; we only need a single representative match for the
-- enrichment.
orders_first as (
    select
        customer_email,
        order_id,
        total_amount as order_total,
        row_number() over (
            partition by customer_email
            order by order_date, order_id
        ) as rn
    from orders
    where customer_email is not null
),

orders_picked as (
    select
        customer_email,
        order_id,
        order_total
    from orders_first
    where rn = 1
),

joined as (
    select
        payments.payment_id,
        payments.customer_id,
        payments.customer_email,
        payments.amount,
        payments.currency,
        payments.created_at,
        orders_picked.order_id,
        orders_picked.order_total,
        orders_picked.order_id is not null as has_matching_order
    from payments
    left join orders_picked
        on payments.customer_email = orders_picked.customer_email
)

select * from joined
