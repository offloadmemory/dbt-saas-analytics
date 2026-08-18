# dbt style guide

This is the project's working style guide for dbt models, names, layers, and materializations. It's based on the official dbt best-practices series — [Overview](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview), [Staging](https://docs.getdbt.com/best-practices/how-we-structure/2-staging), [Intermediate](https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate), [Marts](https://docs.getdbt.com/best-practices/how-we-structure/4-marts) — with the conventions this project has actually adopted pinned at the end of each section so contributors can see both the rationale and the rule.

> **Guiding principle** (from the dbt guide): every transformation should be applied in **only one place**. Move data from **source-conformed** (shaped by systems you don't control) to **business-conformed** (shaped by your organization's needs), and let each layer do one job.

---

## 1. Project layout

```
dbt-saas-analytics/
├── dbt_project.yml          # layer-level materialization rules
├── profiles.yml             # local DuckDB target
├── pyproject.toml           # uv + poethepoet
├── seeds/                   # CSV inputs (one per source)
└── models/
    ├── staging/             # one view per source table; the only place {{ source() }} is used
    ├── intermediate/        # light joins / re-graining between staging and marts
    └── marts/               # business-facing tables; what consumers see
```

Other folders (`macros/`, `tests/`, `snapshots/`, `analyses/`) are kept for the cases the project grows into; they're empty today.

**Rules**

- Three layers, in this order: `staging` → `intermediate` → `marts`. Nothing references a layer above it.
- `seeds/`, `snapshots/`, `macros/`, `tests/`, `analyses/` are siblings of `models/`, not inside it.
- One `profiles.yml` at the project root so dbt finds it without a custom `DBT_PROFILES_DIR`.

---

## 2. Sources

Sources are declared in `models/staging/_sources.yml` (one consolidated file, not per-source), grouped by source system.

**Rules**

- A source is named after the system it comes from (`hubspot`, `stripe`, `zoho`).
- The `schema:` for each source must point at the schema where the data actually lives (for seeds, that's the target schema, e.g. `main`).
- Columns get a `description:` and (for primary keys) a `unique` + `not_null` test in the source yml itself.
- Sources are **only referenced from staging models**. No `{{ source() }}` calls in `intermediate/` or `marts/`.

**This project**

```yaml
# models/staging/_sources.yml
sources:
  - name: hubspot
    schema: main
    tables:
      - name: hubspot_deals
```

---

## 3. Staging layer

**One model per source table, in a subfolder per source system.**

```
models/staging/
├── _sources.yml
├── hubspot/
│   ├── _hubspot__models.yml
│   └── stg_hubspot__deals.sql
├── stripe/
│   ├── _stripe__models.yml
│   └── stg_stripe__payments.sql
└── zoho/
    ├── _zoho__models.yml
    └── stg_zoho__orders.sql
```

### Naming

- `stg_<source>__<entity>.sql` — double underscore between source and entity.
- The leading `stg_` makes staging models a `dbt build --select staging+` selector, which is useful in CI and locally.
- Singular entity name (`stg_hubspot__deal`, not `stg_hubspot__deals`) — staging is one row per source row, but English convention here is to keep the name matching the source table.

### What staging models should do

A staging model has two CTEs and nothing else:

```sql
with source as (
    select * from {{ source('hubspot', 'hubspot_deals') }}
),

renamed as (
    select
        cast(deal_id as integer) as deal_id,
        lower(trim(customer_email)) as customer_email,
        cast(amount as numeric(14, 2)) as amount,
        ...
    from source
)

select * from renamed
```

Allowed transformations:

- ✅ Renaming columns to project-wide conventions.
- ✅ Type casting (`cast(... as ...)`).
- ✅ Basic computations (e.g. cents → dollars, unit conversions).
- ✅ Categorization: booleans or buckets from simple conditionals.
- ✅ Light cleaning: `trim`, `lower`, null-coercion of sentinel strings.

### What staging models should NOT do

- ❌ **Joins** — create duplicated computation and confusing downstream relationships. If a concept requires a join, that concept belongs in `intermediate/`.
- ❌ **Aggregations** — change the grain. You'll lose row-level data you'll need later.
- ❌ **Be queried directly by end users** — staging models are building blocks, not artifacts.

### Materialization

Always `view`. Set it once in `dbt_project.yml` so it's the default for everything under `models/staging/`:

```yaml
models:
  hello_dbt:
    staging:
      +materialized: view
```

Views give downstream models the freshest data, avoid wasting warehouse space on models nobody queries directly, and stay cheap to rebuild.

### Position in the DAG

```
sources → staging → intermediate → marts
```

Staging is the entry point into the project's DAG. The `{{ source() }}` macro should appear in **exactly one place per source table**: the corresponding `stg_*.sql` model.

### Tests

Per staging model, write a sibling `_<source>__models.yml` with:

- `unique` + `not_null` on the primary key.
- `not_null` on columns every downstream join will lean on (e.g. `customer_email`).
- `accepted_values` for any column with a small, known set of values (`stage`, `currency`, etc.).

**This project**

- Staging models live in `models/staging/<source>/`.
- All three are materialized as views, set in `dbt_project.yml`.
- The `stg_stripe__payments` model treats the literal string `'null'` (which DuckDB coerces from an unquoted CSV `null`) as SQL `null` — this is documented inline in the model.

---

## 4. Intermediate layer

**Optional, but useful when a mart needs 4+ joins, re-graining, or complex logic worth isolating.**

```
models/intermediate/
├── _int__models.yml
├── int_payments_enriched.sql
└── int_deals_with_first_payment.sql
```

### Naming

- `int_<entity>_<verb>.sql` — drop the source-system prefix and the double underscore, because at this layer you reference the unified business entity, not system+entity.
- Use a verb: `joined`, `pivoted`, `aggregated_to_user`, `fanned_out_by_quantity`, `summed_to_orders`, `enriched`.
- Examples: `int_payments_enriched`, `int_deals_with_first_payment`, `int_orders_summed_to_customer`.

### What intermediate models should do

- ✅ **Structural simplification** — split a 6-join mart into two intermediates joined at the mart.
- ✅ **Re-graining** — fan out (e.g. orders → order_items by quantity) or collapse (e.g. payments → customer).
- ✅ **Isolate complex logic** — pull a hard transformation into its own model so it can be tested and reasoned about in isolation.

### What intermediate models should NOT do

- ❌ **Be exposed to end users** — intermediate models should not be in the production schema; no BI tool or notebook should query them directly.
- ❌ **Produce multiple outputs** — the DAG should look like an "arrowhead pointed right": multiple inputs into a model are fine, multiple outputs from one model are not. If you need multiple outputs, that's two intermediate models.

### Materialization

Two options, both valid:

- **Ephemeral** (the dbt default recommendation) — inlined into the models that reference them. No physical table. Simpler config, slightly harder to debug.
- **View in a custom schema** — easier to inspect during development, negligible storage cost in DuckDB.

For this project, **view** is the right default because DuckDB makes views essentially free, and being able to `select * from main.int_payments_enriched` during development is worth the tradeoff.

### When to skip the intermediate layer

- A mart can be built cleanly from staging alone (≤3 joins, no re-graining).
- The project is small (<10 marts, no collaboration issues).

### Tests

Same as staging: `unique`/`not_null` on the primary key, plus anything specific to the re-grained or enriched output.

**This project**

- Two intermediate models, both materialized as views (set in `dbt_project.yml`).
- The layer is small and could be skipped; kept because it gives `fct_won_deals` a clean join surface and demonstrates the pattern.

---

## 5. Marts layer

**Business-facing final tables. The first layer that's safe to expose to BI tools, analysts, semantic-layer consumers.**

```
models/marts/
├── _marts__models.yml
├── dim_customers.sql
└── fct_won_deals.sql
```

### Naming

- **One model per business concept, at a clear grain.**
- **Plain English entity names** — `customers`, `orders`, `fct_won_deals`, `dim_customers`.
- The dbt guide does **not** prescribe `fct_` / `dim_` prefixes. This project uses them anyway for one practical reason: when scanning a schema, `fct_` and `dim_` tell you the model's role at a glance. That's a local convention, not a dbt rule.
- Do **not** include time dimensions in mart names. `orders_per_day` is a metric, not a mart.
- If you outgrow a flat folder, group by department/area of concern (e.g. `marts/finance/`, `marts/marketing/`).

#### Fact vs. dimension

The `fct_` and `dim_` prefixes are not arbitrary — they correspond to the two roles a mart serves in a star schema. Pick the prefix based on the **grain** (one row = what?).

| Prefix | Role | Grain | What it holds | Example in this project |
| --- | --- | --- | --- | --- |
| `fct_` | **Fact** | One row per event / transaction / occurrence | Numeric measures (amounts, counts) + foreign keys to dimensions | `fct_payments` (one row per Stripe payment), `fct_won_deals` (one row per closed deal), `fct_pipeline` (one row per Hubspot deal) |
| `dim_` | **Dimension** | One row per unique entity | Descriptive attributes used for filtering/grouping | `dim_customers` (one row per customer) |

**Why the distinction matters:**

- **Cardinality.** A fact typically has many rows per dimension (one customer has many payments). A dimension has one row per entity.
- **Join structure.** Facts sit at the center of a star schema; facts hold foreign keys to dimensions. `fct_payments.customer_id` → `dim_customers.customer_id`.
- **BI tooling.** Most BI tools (Tableau, Looker, Power BI, Metabase) auto-detect `fct_` and `dim_` from the name and treat them differently — facts get measures, dimensions get attributes.
- **Semantic clarity.** A consumer seeing `fct_payments` knows "this is events, I can sum/count/avg the measures." Seeing `dim_customers` knows "this is entities, I use it for filtering/grouping."

**When in doubt:**

- If the model is a **rollup by entity** (one row per customer, summarized across time), it's a `dim_` — even if it has numeric columns. Per-customer totals are still per-customer.
- If the model is an **event log** (one row per payment, deal, ticket, click), it's a `fct_`.
- A common pitfall: a per-customer engagement table reads like a fact ("engagement metrics") but is grain-wise a dimension. Prefix it `dim_`, not `fct_`.

**Naming exception in this project:** `fct_customer_engagement` is misnamed. It's one row per customer (a rollup of engagement metrics across deals, payments, orders), so per the rule above it should be `dim_customer_engagement`. The `fct_` prefix is kept here as a documented local exception — renaming it would break any downstream consumer already querying by the current name. When the project is small enough that no consumer exists, do prefix it `dim_customer_engagement` and update this note.

### What marts should do

- ✅ **One grain** — e.g. one row per customer, one row per Closed-Won deal.
- ✅ **Be wide and denormalized** — pre-join everything a consumer will plausibly need. Storage is cheap, query-time compute is expensive.
- ✅ **Reference intermediate models** when joining more than ~4–5 concepts, so the mart SQL stays readable.
- ✅ **Reference other marts** when it saves compute (e.g. `dim_customers` builds on `fct_orders` rather than re-aggregating payments). Just avoid cycles.

### What marts should NOT do

- ❌ **Mix the same concept for different teams** — if `finance_orders` and `marketing_orders` would compute differently, those are **different concepts** with different names (`tax_revenue`, `gross_revenue`).
- ❌ **Stuff too many concepts into one mart** — if the SQL becomes unreadable, push the complexity into `intermediate/`.
- ❌ **Create time-based rollups** — that's what metrics are for.

### Materialization

Progressive — start simple, add complexity only as needed:

1. **View** — no storage cost, always fresh.
2. **Table** — when the view is too slow to *query*.
3. **Incremental** — when the table is too slow to *build*.

For this project, **marts are tables**. DuckDB is fast enough that the table-vs-view tradeoff is mostly about giving downstream consumers a stable physical artifact, and views don't provide that.

### Tests

The strictest test coverage of any layer — marts are the contract with end users.

- `unique` + `not_null` on the primary key.
- `not_null` on columns every consumer will filter or group on.
- `accepted_values` for low-cardinality columns (`stage`, `currency`, status fields).
- `relationships` tests where a foreign-key relationship is well-defined.
- Singular tests for invariants the schema can't express (e.g. "fct_won_deals has the expected row count after a seed change"). Put these in `tests/` and name them `assert_<model>_<invariant>.sql`.

**This project**

- Two marts: `dim_customers` (one row per customer, surrogate key from `md5(email)`) and `fct_won_deals` (the spiritual successor of the original `models/legacy/won_deals.sql`).
- Both materialized as tables.
- Singular test `tests/assert_fct_won_deals_count.sql` pins the row count to 1 (the number of Closed-Won deals in the seed).

---

## 6. Project configuration

Materializations are set per layer, not per model:

```yaml
# dbt_project.yml
models:
  hello_dbt:
    staging:
      +materialized: view
    intermediate:
      +materialized: view
    marts:
      +materialized: table
```

**Rules**

- Never set `materialized:` in a model file unless it overrides the layer default. If you find yourself doing that, the layer default is probably wrong.
- Keep `clean-targets: ["target", "dbt_packages"]` so `dbt clean` is meaningful.

---

## 7. Tests

- **Schema tests** (generic) live in `_*__models.yml` next to the model. One yml per layer or per source subfolder.
- **Singular tests** (custom SQL) live in `tests/`. Name them `assert_<thing>.sql`.
- Every staging model gets `unique` + `not_null` on its primary key and `not_null` on its most-joined column.
- Every mart gets the strictest coverage of any layer, because marts are the consumer contract.

---

## 8. Quick checklist for adding a new model

1. Is the new table a source? Add it to `models/staging/_sources.yml` with column descriptions and key tests.
2. Will downstream code need a clean, project-conformed version of this source? Yes → add a staging model in `models/staging/<source>/`.
3. Does the new model need to join 4+ things or re-grain data? Yes → `intermediate/`. No → straight to a mart.
4. Is the new model a business-facing concept at a clear grain? Yes → `marts/`.
5. Has the new model been given:
   - Tests for primary key (`unique` + `not_null`)
   - Tests for any low-cardinality string column (`accepted_values`)
   - `not_null` on columns downstream models will join on?
6. Did you write the model with the **two-CTE staging pattern** (`source` + `renamed`) if it's a staging model?

If any of those answers are "I didn't think about it," the model is probably in the wrong layer or has a missing test.

---

# Part II — Style

The structure guide above answers **where** things go. This part answers **how** to write them — file organization, SQL formatting, Jinja, YAML, and naming. It follows the dbt Labs [How we style our dbt projects](https://docs.getdbt.com/best-practices/how-we-style/0-how-we-style-our-dbt-projects) series.

> **Core principle:** *optimize for readers, not writers*. Whitespace is a feature. Match your neighbors. Automate enforcement so humans can write comfortably.

---

## 9. Project-level style

### File organization

- One model per `.sql` file. Filename = model name. No multi-model files.
- The `.sql` file and its documentation `.yml` live in the same directory, with the same base name.
- The very first non-comment line of a model file is `{{ config(...) }}` if the model needs to override layer defaults. Otherwise no config block.
- No `as` aliases on tables. Spell out the full table or CTE name in joins and elsewhere.

### Config blocks

- **Layer-level** materialization lives in `dbt_project.yml`. Don't repeat it per model.
- **Model-specific** config (sort keys, incremental strategy, etc.) lives in a multi-line `{{ config(...) }}` block at the top of the model:

  ```sql
  {{
      config(
          materialized = 'incremental',
          unique_key = 'event_id',
          on_schema_change = 'append_new_columns'
      )
  }}
  ```

- Indent the arguments 4 spaces. Use `=` rather than `:` for consistency with dbt's examples.

### `{{ ref() }}` and `{{ source() }}`

- Use `{{ ref('other_model') }}` to reference any model — staging, intermediate, or mart.
- Use `{{ source('source_name', 'table_name') }}` **only from staging models**. Nothing else in the project should call `{{ source() }}`.
- Never hardcode `database.schema.table` references. Always go through `ref()` or `source()`.

### Imports at the top

The first CTEs in a model should be the "import" CTEs — one per upstream model, named after the table they reference:

```sql
with deals as (
    select * from {{ ref('stg_hubspot__deals') }}
),

payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

...
```

This makes the file scannable: the top tells you what the model depends on, the rest tells you what it does with that data.

**This project** — every model in this repo starts with one or more import CTEs (`source` for staging models, named-after-the-ref for everything else), then functional CTEs, then a final `select * from <final_cte>`.

---

## 10. SQL style

### Case

- **Keywords**: lowercase (`select`, `from`, `where`, `case`, `when`, `end`).
- **Functions**: lowercase (`sum`, `coalesce`, `cast`, `date`, `lower`).
- **Identifiers**: lowercase, `snake_case` (`customer_id`, `total_deal_amount`).
- **No** `SELECT *` in column lists you actually mean to project. `select *` is fine for the final `select * from <final_cte>` line and for import CTEs that are passing everything through.
- **Explicit `as`**: `count(*) as n`, never `count(*) n`.

### Indentation and whitespace

- **4 spaces** per indent level. No tabs.
- Generous blank lines between logical blocks: one between CTEs, one before the final `select`.
- Newlines around major clauses (`select` list, `from`, `join`, `where`, `group by`, `order by`).
- Don't fight SQLFluff to keep lines under 80 chars in this project — the project's `.sqlfluff` sets `max_line_length = 0` (unlimited) and that's intentional for readability of longer expressions. The dbt guide's 80-char rule is the default; this repo opts out.

### Commas

- **Trailing** commas (comma at end of line, not start). The dbt guide allows either; trailing is the more common dbt Labs convention.
- Each `select`-list item on its own line.

### Joins

- **Always prefix columns with the table or CTE name** when joining two or more sources. In a single-table query, no prefix needed.
- **Be explicit about the join type**: `inner join`, `left join`, `right join` — never bare `join`.
- **No table aliases** (`from customers c` is forbidden; spell out `from customers`).
- **No `right join`** — restructure the query so the "primary" table is on the left.
- **`on` clause on its own line, indented:**

  ```sql
  left join payments
      on deals.customer_email = payments.customer_email
  ```

- **`union all` over `union`** unless duplicate removal is explicitly required (it almost never is).

### `group by`

- **Prefer `group by 1, 2` (positional) over listing column names.** If you find yourself grouping by many columns, the model is probably doing too much and should be split.

### `where` / `having`

- `where` precedes `having`.
- For complex predicates, break lines so the boolean structure is visible:

  ```sql
  where customer_email is not null
      and (
          stage = 'Closed-Won'
          or stage = 'Closed-Lost'
      )
  ```

### `case`

- `when` / `then` on their own lines, indented:

  ```sql
  case
      when first_payment_at is not null and close_date is not null
          then date_diff('day', first_payment_at, close_date)
  end as days_to_first_payment
  ```

### CTEs

- One logical unit of work per CTE.
- Verbose, descriptive names: `orders_joined_to_customers`, not `joined`.
- The final line of every model is `select * from <final_cte>`. This lets a reviewer/developer change the CTE name in that one line to inspect any intermediate step.
- If two models need the same CTE logic, extract it into an `intermediate` model — don't duplicate the CTE.

### Subqueries

- Don't use them. If logic is reused, it goes in an intermediate model.

**This project** — `.sqlfluff` config (at the repo root) sets most of these rules explicitly: `extended_capitalisation_policy = lower` for keywords/functions/identifiers/types, `tab_space_size = 2` (this project deviates from dbt's 4-space rule — the existing `.sqlfluff` predates the rebuild and uses 2), `aliasing.table = explicit` and `aliasing.column = explicit` (enforces the "no aliases" rule above), `capitalisation.literals = upper` for `null`/`true`/`false` literals (DuckDB accepts both, but the linter enforces `NULL`/`TRUE`/`FALSE`).

---

## 11. Jinja style

### Whitespace

- **Spaces inside delimiters**: write `{{ this }}`, not `{{this}}`. Same for `{% ... %}`.
- **Newlines to mark logical blocks** of Jinja — a `{% if %}` / `{% for %}` block reads better with blank lines around it.
- **4-space indent** inside a Jinja block. (This project uses 2 to match the rest of the SQL — see note above.)
- **Don't fight whitespace control** (`{%- ... -%}`) for cosmetic reasons. Compiled SQL doesn't have to be pretty; the model source does.

### Control flow

- `{% if %}` / `{% else %}` / `{% endif %}` and `{% for %}` / `{% endfor %}` follow the same 4-space (or project-default) indent rule as the surrounding SQL.
- Use Jinja comments `{# ... #}` for notes that should **not** appear in compiled SQL. Use SQL comments `-- ...` for notes that **should** appear (e.g. for someone reading the warehouse query log).

### Macros

- Macro names are `snake_case`, verb-led when they perform an action: `cents_to_dollars`, `pivot_columns`, `generate_surrogate_key`.
- One macro per file, file named the same as the macro (`macros/cents_to_dollars.sql`).
- Macros take arguments by position or keyword; document each in a header comment.
- Prefer pure functions: a macro should not depend on the calling model's state.

### When to use Jinja

Jinja is for repetition and conditional logic, not for hiding logic. If a reader has to mentally execute Jinja to understand the SQL, the SQL should be rewritten.

**This project** — uses `{{ config(...) }}`, `{{ ref(...) }}`, `{{ source(...) }}`, and `{{ this }}` (in macros). No `set` blocks, no `for` loops, no `if` blocks in models. Jinja stays minimal.

---

## 12. YAML style

### Indentation

- **2 spaces.** No tabs. (Both dbt's guide and this project agree.)
- List items (lines beginning with `- `) are indented under their parent key.

### Quoting

- Quote any string that contains a colon, parentheses, or other YAML-significant punctuation. Bare strings otherwise.
- Multi-word descriptions don't need quotes unless they contain punctuation.

### Line length

- Wrap descriptions to ≤ 80 chars. (This project is lax on this; the dbt guide is firm.)

### Lists

- **Always use explicit list form** for a single-entry list: `tags: ['daily']` not `tags: 'daily'`. Bare strings are technically valid but discouraged.
- **Blank line between dict list items.** A list of dicts is more readable when each entry is separated:

  ```yaml
  models:
    - name: customers
      description: "..."

    - name: orders
      description: "..."
  ```

### Top-level shape

- Start with `version: 2`.
- One `_*__models.yml` per layer / source subfolder. Don't put all models in one giant yml.
- Sources go in `_sources.yml`, not interleaved with model docs.

### Generic test arguments

In dbt 1.10.5+, arguments to generic tests must be nested under `arguments:`:

```yaml
data_tests:
  - unique
  - not_null
  - relationships:
      arguments:
        to: ref('users')
        field: id
  - accepted_values:
      arguments:
        values: ['Closed-Won', 'Closed-Lost']
```

Putting the args at the top level (without `arguments:`) is a deprecation warning as of dbt 1.10.

**This project** — all yml files in this repo follow the 2-space indent, explicit list form, blank-line-between-dicts, and `arguments:`-nested test args. The dbt-checkpoint pre-commit hooks are not configured; sqlfluff is the active linter today.

---

## 13. Naming conventions

### Models

- `snake_case`.
- Plural or singular — match the dbt Labs convention used in the dbt guide: `customers` (plural) for marts, `stg_<source>__<entity>` (singular entity, plural source table name) for staging. This project uses singular for staging because the source CSV names are singular (`hubspot_deals` → `stg_hubspot__deal` is wrong; the model is `stg_hubspot__deals` to match the source).
- **No dots in model names.** Dots collide with `database.schema.object` syntax and force quoting.
- **No abbreviations**: `customer` not `cust`, `payment` not `pay`.

### Columns

- `snake_case`.
- **Primary keys** are `<object>_id`: `deal_id`, `customer_id`, `payment_id`. Never bare `id`.
- **Foreign keys** match the primary key they reference: a `customer_id` column in `orders` references `customers.customer_id`. Don't rename it to `user_id` or `account_id` in one model and `customer_id` in another.
- **Timestamps**: `<event>_at` in UTC. `created_at`, `ordered_at`, `paid_at`. If not UTC, suffix the timezone: `created_at_pt`.
- **Dates**: `<event>_date`. `order_date`, `close_date`.
- **Event columns** are past tense: `created`, `updated`, `deleted`, `closed`, `paid`.
- **Booleans** start with `is_` or `has_`: `is_active`, `has_matching_order`.
- **Money**: decimal currency, e.g. `19.99`. If you must use integer cents, suffix with `_in_cents` so the unit is obvious.
- **Surrogate keys** computed in dbt follow the same `<object>_id` rule: `dim_customers.customer_id` is `md5(email)`.
- **No reserved words** as column names.

### Column ordering in `select` lists

When you write a model, organize the `select` list in this order, with comment banners:

```sql
select
    ---------- ids
    deal_id,
    customer_id,

    ---------- strings
    deal_name,
    deal_owner,
    customer_email,

    ---------- numerics
    amount,
    total_deal_amount,

    ---------- booleans
    is_active,
    has_matching_order,

    ---------- dates
    close_date,
    order_date,

    ---------- timestamps
    created_at,
    first_payment_at
```

This is purely a readability rule — the warehouse doesn't care — but a consistent order across the project makes models scannable.

**This project** — most staging models in this repo follow the order above. The mart `fct_won_deals` reorders to put `deal_id`/`customer_id` first, then deal attributes, then the enrichment (`first_payment_at`, `days_to_first_payment`).

---

## 14. Enforcement

This project currently has:

- **sqlfluff** (configured at the repo root, `.sqlfluff`) — lints SQL. Run with `uv run sqlfluff lint models/`.

This project does **not** have:

- `pre-commit` (the dbt Labs guide recommends it, but it adds a Python dev dependency and a `.pre-commit-config.yaml`. Skipped for now to keep `pyproject.toml` minimal.)
- `dbt-checkpoint` (recommended by dbt Labs; a pre-commit-friendly set of dbt-specific hooks. Consider adding if the project grows.)

When the project outgrows manual review, the recommended next step is `pre-commit` + `dbt-checkpoint`. Don't add a tool without a reason.

---

## References

- [Guide overview (structure)](https://docs.getdbt.com/best-practices/how-we-structure/1-guide-overview)
- [Staging](https://docs.getdbt.com/best-practices/how-we-structure/2-staging)
- [Intermediate](https://docs.getdbt.com/best-practices/how-we-structure/3-intermediate)
- [Marts](https://docs.getdbt.com/best-practices/how-we-structure/4-marts)
- [How we style our dbt projects (overview)](https://docs.getdbt.com/best-practices/how-we-style/0-how-we-style-our-dbt-projects)
- [How we style our dbt models](https://docs.getdbt.com/best-practices/how-we-style/1-how-we-style-our-dbt-models)
- [How we style our SQL](https://docs.getdbt.com/best-practices/how-we-style/2-how-we-style-our-sql)
- [How we style our Jinja](https://docs.getdbt.com/best-practices/how-we-style/4-how-we-style-our-jinja)
- [How we style our YAML](https://docs.getdbt.com/best-practices/how-we-style/5-how-we-style-our-yaml)
- [Conclusion](https://docs.getdbt.com/best-practices/how-we-style/6-how-we-style-conclusion)
