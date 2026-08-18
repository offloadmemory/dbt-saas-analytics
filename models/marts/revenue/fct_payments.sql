{{ config(materialized='table') }}

-- Revenue fact: one row per Stripe payment, with customer dimension and
-- matched Zoho order context. Use this for any revenue reporting (monthly
-- revenue, customer LTV, currency mix, etc).

with payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

orders as (
    select * from {{ ref('stg_zoho__orders') }}
),

-- For each payment, find the customer's matching Zoho order (if any).
-- Used to flag conversion: payment preceded by an order.
payment_order_match as (
    select
        payments.payment_id,
        orders.order_id as matched_order_id,
        orders.total_amount as matched_order_total,
        orders.order_date as matched_order_date
    from payments
    left join orders
        on lower(trim(payments.customer_email)) = orders.customer_email
),

final as (
    select
        payments.payment_id,
        payments.customer_id,
        payments.customer_email,
        payments.amount,
        payments.currency,
        payments.created_at,
        payment_order_match.matched_order_id,
        payment_order_match.matched_order_total,
        payment_order_match.matched_order_date,
        case
            when payment_order_match.matched_order_id is not null then true
            else false
        end as has_matching_order
    from payments
    left join customers
        on payments.customer_email = customers.customer_email
    left join payment_order_match
        on payments.payment_id = payment_order_match.payment_id
)

select * from final
