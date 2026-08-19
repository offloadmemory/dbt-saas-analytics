-- Singular test: assert the Closed-Won deal's `days_to_first_payment` is
-- exactly 45 (close_date 2022-02-15 minus first_payment_at 2022-01-01).
-- Catches a sign-flip or unit-mismatch bug from the `datediff(...)` call in
-- fct_won_deals.sql. The existing count-based test only catches row-count
-- regressions, not value regressions; this test complements it.
--
-- Update `expected_value` when the seed changes.

{{ config(severity='error') }}

with actual as (
    select days_to_first_payment
    from {{ ref('fct_won_deals') }}
    where deal_id = 1
),

expected as (
    select 45 as days_to_first_payment
)

select
    a.days_to_first_payment as actual_value,
    e.days_to_first_payment as expected_value
from actual a
cross join expected e
where a.days_to_first_payment is null
   or a.days_to_first_payment != e.days_to_first_payment
