-- Singular test: assert `emily.white@example.com` has `last_engagement_at =
-- 2022-03-18 00:00:00`. That customer has no Hubspot deal, a Stripe payment on
-- 2022-01-04 09:30:00, and a Zoho order on 2022-03-18 — so the most recent
-- signal is her Zoho order. Catches a `greatest(...)` type-mismatch on the
-- Databricks adapter (which would fail at compile time on mixed DATE /
-- TIMESTAMP args) or any silent coercion bug.
--
-- Update `expected_ts` when the seed changes.

{{ config(severity='error') }}

with actual as (
    select last_engagement_at
    from {{ ref('fct_customer_engagement') }}
    where customer_email = 'emily.white@example.com'
),

expected as (
    select timestamp '2022-03-18 00:00:00' as last_engagement_at
)

select
    a.last_engagement_at as actual_value,
    e.last_engagement_at as expected_value
from actual a
cross join expected e
where a.last_engagement_at is null
   or a.last_engagement_at != e.last_engagement_at
