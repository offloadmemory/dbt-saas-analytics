-- Singular test: assert the mart's row count matches the expected value.
-- Update `expected` when the seed changes. A failure here means either
-- (a) the seed was edited (intentional change to expected), or
-- (b) the staging filter or join logic changed unexpectedly.

{{ config(severity='error') }}

with actual as (
    select count(*) as n from {{ ref('fct_won_deals') }}
),

expected as (
    select 1 as n
)

select *
from actual
where actual.n != (select n from expected)
   or actual.n < 0
