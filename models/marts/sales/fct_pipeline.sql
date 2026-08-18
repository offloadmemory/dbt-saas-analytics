{{ config(materialized='table') }}

-- Sales pipeline fact: one row per Hubspot deal, ALL stages (not just
-- Closed-Won). Use this for pipeline coverage, win rate by rep, deals
-- by stage, forecasting, etc. The Closed-Won subset is exposed as
-- fct_won_deals in the same domain.

with deals as (
    select * from {{ ref('stg_hubspot__deals') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

final as (
    select
        deals.deal_id,
        deals.deal_name,
        deals.deal_owner,
        deals.amount,
        deals.close_date,
        deals.stage,
        deals.customer_email,
        customers.customer_id,
        case
            when deals.stage = 'Closed-Won' then 'won'
            when deals.stage = 'Closed-Lost' then 'lost'
            else 'open'
        end as deal_outcome
    from deals
    left join customers
        on deals.customer_email = customers.customer_email
)

select * from final
