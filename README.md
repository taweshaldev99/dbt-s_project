# DBT Banking Data Engineering Project

A dbt project on PostgreSQL that builds a **Bronze → Silver → Gold** pipeline from a banking dataset (customers, branches, products, accounts, cards and historical transactions) and calculates banking KPIs, including the **CASA Ratio**.

## Contents

- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Setup](#setup)
- [Running the pipeline](#running-the-pipeline)
- [Layers in detail](#layers-in-detail)
- [Incremental models and snapshot demo](#incremental-models-and-snapshot-demo)
- [Banking KPIs](#banking-kpis)
- [Data quality tests](#data-quality-tests)
- [Assumptions and data notes](#assumptions-and-data-notes)
- [Project status](#project-status)

## Architecture

```
insert.sql
    │
    ▼
┌────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│  BRONZE    │ ──▶ │  SILVER         │ ──▶ │  GOLD                │
│  raw data  │     │  models/staging │     │  models/marts        │
│  (6 tables)│     │  cleaned data   │     │  dims, facts, KPIs   │
└────────────┘     └─────────────────┘     └──────────────────────┘
                          │
                          ▼
                   snapshots/ (history of account changes)
```

| Layer | Schema | Purpose |
|---|---|---|
| Bronze | `bronze` | Raw source tables, loaded as-is |
| Silver | `silver` | Cleaned and standardised staging models |
| Gold | `gold` | Dimensions, facts and KPIs for reporting |
| Snapshots | `snapshots` | Historical versions of changing records |

Table relationships:

```
customer ── account ──┬── product
                      ├── branch
                      ├── card
                      └── hist_transactional
```

## Tech stack

- PostgreSQL
- dbt Core with the `dbt-postgres` adapter
- Python (virtual environment `proj`)
- VS Code with SQLTools for running SQL

## Project structure

```
dbt_project/
├── dbt_project.yml
├── macros/
│   └── generate_schema_name.sql     # plain schema names: silver, gold
├── seeds/
│   └── fx_rates.csv                 # exchange rates to NPR
├── models/
│   ├── staging/                     # Silver layer
│   │   ├── source.yml
│   │   ├── schema.yml
│   │   ├── stg_customer.sql
│   │   ├── stg_branch.sql
│   │   ├── stg_product.sql
│   │   ├── stg_account.sql          # incremental (merge)
│   │   ├── stg_card.sql
│   │   └── stg_hist_transactional.sql  # incremental (append)
│   └── marts/                       # Gold layer
│       ├── schema.yml
│       ├── dimensions/
│       │   ├── dim_customer.sql
│       │   ├── dim_branch.sql
│       │   ├── dim_product.sql
│       │   ├── dim_account.sql
│       │   └── dim_card.sql
│       ├── facts/
│       │   ├── fct_account_balance.sql
│       │   └── fct_transactions.sql
│       └── kpis/
│           ├── kpi_definitions.sql
│           ├── kpi_account.sql
│           ├── kpi_transactions.sql
│           └── kpi_summary.sql
├── snapshots/
│   └── snap_account.sql
└── tests/
    ├── assert_no_negative_non_loan_balance.sql
    └── assert_casa_ratio_between_0_and_1.sql
```

> dbt project names cannot contain hyphens, so the internal name is `dbt_project`. The assignment's `dbt-project` is the name of the submitted folder or repository.

## Setup

### 1. Prerequisites
- Python 3.9 or newer
- PostgreSQL running locally (the `merge` incremental strategy needs PostgreSQL 15 or newer and dbt-postgres 1.9 or newer)

### 2. Create the environment and install dbt
```bash
python -m venv proj
proj\Scripts\activate          # Windows
# source proj/bin/activate     # macOS / Linux
pip install dbt-core dbt-postgres
```

### 3. Configure the connection
Create `~/.dbt/profiles.yml` (on Windows, `C:\Users\<you>\.dbt\profiles.yml`), or keep a `profiles.yml` next to `dbt_project.yml`:

```yaml
dbt_project:
  target: dev
  outputs:
    dev:
      type: postgres
      host: localhost
      port: 5432
      user: <your_user>
      password: <your_password>
      dbname: postgres
      schema: public
      threads: 2
```

Do not commit this file. It is listed in `.gitignore`.

### 4. Verify the connection
```bash
cd dbt_project
dbt debug
```
You should see `All checks passed!`.

### 5. Load the Bronze data
Run `insert.sql` against PostgreSQL after adding these two lines at the very top:

```sql
CREATE SCHEMA IF NOT EXISTS bronze;
SET search_path TO bronze;
```

Check the load:

```sql
select 'customer' as table_name, count(*) as row_count from bronze.customer union all
select 'branch', count(*) from bronze.branch union all
select 'product', count(*) from bronze.product union all
select 'account', count(*) from bronze.account union all
select 'card', count(*) from bronze.card union all
select 'hist_transactional', count(*) from bronze.hist_transactional;
```

Expected counts:

| Table | Rows |
|---|---|
| customer | 50 |
| branch | 30 |
| product | 15 |
| account | 150 |
| card | 60 |
| hist_transactional | 400 |

## Running the pipeline

Run all commands from inside the `dbt_project` folder.

```bash
dbt deps                 # only if packages.yml exists
dbt seed                 # load fx_rates
dbt run -s staging       # build Silver
dbt snapshot             # build snapshot (baseline)
dbt run -s marts         # build Gold
dbt test                 # run data quality tests
```

Or build everything in dependency order:

```bash
dbt build
```

Generate and view the documentation and lineage graph:

```bash
dbt docs generate
dbt docs serve
```

Rebuild an incremental model from scratch:

```bash
dbt run -s stg_account stg_hist_transactional --full-refresh
```

## Layers in detail

### Bronze
Raw tables created from `insert.sql`, with no business transformation. They are declared in `models/staging/source.yml` and accessed with `{{ source('bronze', '<table>') }}`.

### Silver (staging)
Cleaned and standardised versions of each Bronze table:

- Data type casting
- `TRIM()` and `UPPER()` / `INITCAP()` on text fields
- Null handling with `COALESCE`
- Duplicate removal with `ROW_NUMBER()`
- Date and timestamp standardisation
- Business-rule validation (for example: only loans may have negative balances, valid scheme types, valid card types)
- Joins to enforce referential integrity (for example: cards and transactions must belong to an existing account)
- Standardised column names and added flags such as `is_closed`, `is_expired`, `tran_direction`

### Gold (marts)
**Dimensions:** `dim_customer`, `dim_branch`, `dim_product`, `dim_account`, `dim_card`

**Facts:**
- `fct_account_balance`: one row per account, with the balance converted to NPR
- `fct_transactions`: one row per transaction, with the amount converted to NPR and a signed amount (credit positive, debit negative)

**KPIs:** see below.

## Incremental models and snapshot demo

### `stg_account`: incremental MERGE
- Strategy: `merge`, unique key `account_id`
- First run: full load
- Later runs: only rows where `lchg_time` is newer than the current maximum in the table are processed. Changed accounts are updated and new accounts are inserted.

Demo (run in PostgreSQL, then run `dbt run -s stg_account`):

```sql
UPDATE bronze.account
SET account_balance = account_balance + 50000, lchg_time = now()
WHERE account_id = 'AC000002';

INSERT INTO bronze.account
  (account_id, customer_id, branch_id, account_balance, lien_amt,
   acct_cls_flg, product_id, schm_type, schm_code, acct_crncy_code)
VALUES ('AC000151', 'C0001', 'BR001', 25000, 0, 'N', 'PRD001', 'SA', 'SAV001', 'NPR');
```

The dbt log should show only the changed and new rows being merged, not all 150.

### `stg_hist_transactional`: incremental APPEND
- Strategy: `append`
- Only transactions with a `created_date` newer than the current maximum are added, so history is never reloaded.

Demo:

```sql
INSERT INTO bronze.hist_transactional
VALUES ('TXN0000401', 'AC000002', 'BR008', 15000, 'NPR', current_date,
        'Cash Deposit', 'Deposited at branch counter', now(), now());
```

Run `dbt run -s stg_hist_transactional`. The log should show `INSERT 0 1`.

### Snapshot: `snap_account`
Tracks changes to `account_balance`, `acct_cls_flg`, `branch_id` and `product_id` using the `check` strategy.

1. Run `dbt snapshot` before changing any data (baseline).
2. Change an account in Bronze, then run `dbt run -s stg_account`.
3. Run `dbt snapshot` again.
4. View the history:

```sql
select account_id, account_balance, branch_id, dbt_valid_from, dbt_valid_to
from snapshots.snap_account
where account_id = 'AC000002'
order by dbt_valid_from;
```

The old version has a `dbt_valid_to` value. The current version has `dbt_valid_to` = NULL.

## Banking KPIs

All KPIs are calculated from Gold-layer data. Each one has a name, business definition, formula, SQL implementation (`kpi_account`, `kpi_transactions`) and grouping. Definitions live in `kpi_definitions` and results are joined in `kpi_summary`.

| # | KPI | Business definition | Formula | Grouping |
|---|---|---|---|---|
| 1 | **CASA Ratio** | Share of deposits held in current and savings accounts | (CA + SA) / (CA + SA + TD) | Branch, province, overall |
| 2 | Total Deposits | Balance of all open deposit accounts | SUM(balance) for CASA and term deposits | Branch, province, overall |
| 3 | Loan Portfolio | Outstanding amount on open loan accounts | SUM(ABS(balance)) for LD | Branch, province, overall |
| 4 | Loan to Deposit Ratio | Share of deposits lent out | Loan Portfolio / Total Deposits | Branch, province, overall |
| 5 | Active Accounts | Number of open accounts | COUNT(accounts) where `acct_cls_flg = 'N'` | Branch, province, overall |
| 6 | Average Deposit Balance | Average balance per open deposit account | AVG(balance) | Product category |
| 7 | Account Closure Rate | Share of accounts that are closed | Closed accounts / All accounts | Product category |
| 8 | Accounts per Customer | Average open accounts per customer | Open accounts / Distinct customers | Overall |
| 9 | Card Penetration | Share of open accounts with a card | Accounts with a card / Open accounts | Overall |
| 10 | Transaction Count | Number of transactions | COUNT(tran_id) | Month |
| 11 | Transaction Value | Total transaction value in NPR | SUM(tran_amount_npr) | Month |
| 12 | Net Cash Flow | Inflows minus outflows in NPR | SUM(credits) - SUM(debits) | Month |

Check the required KPI:

```sql
select * from gold.kpi_summary where kpi_name = 'CASA Ratio' order by grain, grain_value;
```

## Data quality tests

**Generic tests** (in `schema.yml` files):
- `unique` and `not_null` on all primary keys
- `relationships` between account, customer, branch, product, card and transactions
- `accepted_values` for `schm_type`, `acct_cls_flg`, `card_type` and `tran_direction`

**Singular tests** (in `tests/`):
- `assert_no_negative_non_loan_balance`: only loan accounts may have negative balances
- `assert_casa_ratio_between_0_and_1`: the CASA ratio must be a valid ratio

Run them with `dbt test`.

## Assumptions and data notes

- **TD (term deposit) = FD + RD.** The data has scheme types `SA`, `CA`, `FD`, `RD` and `LD`, and no `TD`. Change the `product_group` logic in `dim_product` if TD should mean FD only.
- **Loans (`LD`) have negative balances** and are excluded from the CASA ratio.
- **Balance KPIs use open accounts only** (`acct_cls_flg = 'N'`) and NPR-converted amounts.
- **Currency conversion** uses `seeds/fx_rates.csv`. The rates are illustrative and should be replaced for real reporting.
- **Transaction direction** is derived from `tran_particular`. Mobile Banking Transfer is treated as a debit (outward).
- **Data quirks are flagged, not dropped:** some phone numbers do not have 10 digits (`is_valid_phone`), and some cards are already expired (`is_expired`). Debit cards have a NULL `closing_balance` by design.
- **`lchg_time` is identical for all rows at load time**, so the incremental merge only shows activity after some rows are updated.

## Project status

- [x] dbt installed and connection verified (`dbt debug`)
- [x] Bronze layer loaded (6 tables)
- [x] Project configuration, schema macro and sources
- [x] `fx_rates` seed
- [ ] Silver staging models (6)
- [ ] Incremental merge and append demos
- [ ] Snapshot
- [ ] Gold dimensions (5)
- [ ] Gold facts (2)
- [ ] Banking KPIs (at least 10, including CASA Ratio)
- [ ] Data quality tests
- [ ] `dbt build` passing, docs and lineage graph

Tick the boxes as you complete each step.

## Author

Taweshal Dev Thakur
