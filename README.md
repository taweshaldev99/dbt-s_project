# DBT Banking Data Engineering Project

A dbt project on PostgreSQL that builds a **Bronze → Silver → Gold** pipeline from a banking dataset (customers, branches, products, accounts, cards and historical transactions) and calculates 12 banking KPIs, including the required **CASA Ratio**.

**Result:** `dbt build` completes with `PASS=57 WARN=0 ERROR=0` (1 seed, 6 staging models, 2 incremental models, 1 snapshot, 5 dimensions, 2 facts, 4 KPI models and 38 data tests).

## Contents

- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Repository structure](#repository-structure)
- [Setup](#setup)
- [Running the pipeline](#running-the-pipeline)
- [Layers in detail](#layers-in-detail)
- [Incremental models and snapshot](#incremental-models-and-snapshot)
- [Banking KPIs](#banking-kpis)
- [Data quality tests](#data-quality-tests)
- [Verified results](#verified-results)
- [Assumptions and design decisions](#assumptions-and-design-decisions)
- [Troubleshooting](#troubleshooting)

## Architecture

```
source_data/insert.sql
        │
        ▼
┌────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│  BRONZE    │ ──▶ │  SILVER         │ ──▶ │  GOLD                │
│  raw data  │     │  models/staging │     │  models/marts        │
│  6 tables  │     │  cleaned data   │     │  dims, facts, KPIs   │
└────────────┘     └─────────────────┘     └──────────────────────┘
                          │
                          ▼
                   snapshots/snap_account
                   (history of account changes)
```

| Layer | Schema | Purpose |
|---|---|---|
| Bronze | `bronze` | Raw source tables, loaded as-is |
| Silver | `silver` | Cleaned and standardised staging models, plus the `fx_rates` seed |
| Gold | `gold` | Dimensions, facts and KPIs for reporting |
| Snapshots | `snapshots` | Historical versions of changing account records |

Source table relationships:

```
customer ── account ──┬── product
                      ├── branch
                      ├── card
                      └── hist_transactional
```

## Tech stack

- PostgreSQL
- dbt Core 1.12 with the `dbt-postgres` adapter
- Python virtual environment
- VS Code with SQLTools for running SQL

## Repository structure

```
dbt-project/
├── README.md
├── requirements.txt
├── profiles.yml.example          # connection template (copy to ~/.dbt/profiles.yml)
├── dbt_project.yml
├── source_data/
│   ├── insert.sql                # creates and loads the Bronze tables
│   └── insert_to_postgres.py     # optional Python loader (targets schema "bronze")
├── macros/
│   └── generate_schema_name.sql  # plain schema names: silver, gold
├── seeds/
│   └── fx_rates.csv              # exchange rates to NPR
├── models/
│   ├── staging/                  # Silver layer
│   │   ├── sources.yml
│   │   ├── schema.yml
│   │   ├── stg_customer.sql
│   │   ├── stg_branch.sql
│   │   ├── stg_product.sql
│   │   ├── stg_account.sql              # incremental (merge)
│   │   ├── stg_card.sql
│   │   └── stg_hist_transactional.sql   # incremental (append)
│   └── marts/                    # Gold layer
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

> dbt project names cannot contain hyphens, so the internal project name is `dbt_project`. `dbt-project` is the name of the repository folder.

## Setup

### 1. Prerequisites
- Python 3.9 or newer
- PostgreSQL running locally. The `merge` incremental strategy needs PostgreSQL 15 or newer and dbt-postgres 1.9 or newer.

### 2. Create the environment and install dbt
```bash
python -m venv proj
proj\Scripts\activate          # Windows
# source proj/bin/activate     # macOS / Linux
pip install -r requirements.txt
```

### 3. Configure the connection
Copy `profiles.yml.example` to `~/.dbt/profiles.yml` (on Windows: `C:\Users\<you>\.dbt\profiles.yml`) and fill in your own credentials. Never commit this file.

### 4. Verify the connection
```bash
dbt debug
```
You should see `All checks passed!`.

### 5. Load the Bronze data
**Option A: SQL.** Add these two lines at the very top of `source_data/insert.sql`, then run the whole file against your database:
```sql
CREATE SCHEMA IF NOT EXISTS bronze;
SET search_path TO bronze;
```

**Option B: Python.** The script creates the `bronze` schema itself:
```bash
python source_data/insert_to_postgres.py --drop
```
Set `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and `PGPASSWORD` first. Use the same database as in `profiles.yml`.

Check the load:
```sql
select 'customer' as table_name, count(*) as row_count from bronze.customer union all
select 'branch', count(*) from bronze.branch union all
select 'product', count(*) from bronze.product union all
select 'account', count(*) from bronze.account union all
select 'card', count(*) from bronze.card union all
select 'hist_transactional', count(*) from bronze.hist_transactional;
```

| Table | Rows |
|---|---|
| customer | 50 |
| branch | 30 |
| product | 15 |
| account | 150 |
| card | 60 |
| hist_transactional | 400 |

## Running the pipeline

Run all commands from the folder that contains `dbt_project.yml`.

```bash
dbt seed                 # load fx_rates
dbt run -s staging       # build Silver
dbt snapshot             # build the snapshot (baseline)
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
If `dbt docs generate` fails with "two relations ... similar database identifiers", see [Troubleshooting](#troubleshooting).

Rebuild the incremental models from scratch:
```bash
dbt run -s stg_account stg_hist_transactional --full-refresh
```

## Layers in detail

### Bronze
Raw tables created from `insert.sql`, with no business transformation. They are declared in `models/staging/sources.yml` and accessed with `{{ source('bronze', '<table>') }}`.

### Silver (staging)
Cleaned and standardised versions of each Bronze table:

- Data type casting
- `TRIM()` and `UPPER()` / `INITCAP()` on text fields
- Null handling with `COALESCE`
- Duplicate removal with `ROW_NUMBER()`
- Date and timestamp standardisation
- Business-rule validation (only loans may have negative balances, valid scheme types, valid card types)
- Joins that enforce referential integrity (cards and transactions must belong to an existing account)
- Standardised column names and derived flags such as `is_closed`, `is_expired`, `is_valid_phone` and `tran_direction`

### Gold (marts)
**Dimensions:** `dim_customer`, `dim_branch`, `dim_product` (adds `product_category` and `product_group`), `dim_account`, `dim_card`

**Facts:**
- `fct_account_balance`: one row per account, with the balance converted to NPR
- `fct_transactions`: one row per transaction, with the amount converted to NPR and a signed amount (credits positive, debits negative)

**KPIs:** see below.

## Incremental models and snapshot

### `stg_account`: incremental MERGE
- Strategy `merge`, unique key `account_id`
- First run: full load
- Later runs: only rows where `lchg_time` is newer than the current maximum in the table are processed. Changed accounts are updated and new accounts are inserted.

**Demo.** Change data in Bronze, then run `dbt run -s stg_account`:
```sql
update bronze.account
set account_balance = account_balance + 50000, lchg_time = now()
where account_id = 'AC000002';

update bronze.account
set branch_id = 'BR001', lchg_time = now()
where account_id = 'AC000004';

insert into bronze.account
  (account_id, customer_id, branch_id, account_balance, lien_amt,
   acct_cls_flg, product_id, schm_type, schm_code, acct_crncy_code)
values ('AC000151', 'C0001', 'BR001', 25000, 0, 'N', 'PRD001', 'SA', 'SAV001', 'NPR');
```
The dbt log shows `MERGE 3` (two updates and one insert), not a reload of all 150 rows. A second run with no new changes shows `MERGE 0`.

### `stg_hist_transactional`: incremental APPEND
- Strategy `append`
- Only transactions with a `created_date` newer than the current maximum are added, so history is never reloaded.

**Demo:**
```sql
insert into bronze.hist_transactional
values ('TXN0000401', 'AC000002', 'BR008', 15000, 'NPR', current_date,
        'Cash Deposit', 'Deposited at branch counter', now(), now());
```
Running `dbt run -s stg_hist_transactional` appends one row (`INSERT 0 1`).

### Snapshot: `snap_account`
Tracks changes to `account_balance`, `acct_cls_flg`, `branch_id` and `product_id` using the `check` strategy, built from `stg_account`.

1. Run `dbt snapshot` before changing any data (baseline).
2. Change an account in Bronze and run `dbt run -s stg_account`.
3. Run `dbt snapshot` again.
4. View the history:
```sql
select account_id, account_balance, branch_id, dbt_valid_from, dbt_valid_to
from snapshots.snap_account
where account_id = 'AC000002'
order by dbt_valid_from;
```
The old version has a `dbt_valid_to` value and the current version has `dbt_valid_to` = NULL.

## Banking KPIs

All KPIs are calculated from Gold-layer data. Each one has a name, business definition, formula, SQL implementation and grouping. Definitions live in `kpi_definitions`, implementations in `kpi_account` and `kpi_transactions`, and the combined output in `kpi_summary`.

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

Query the required KPI:
```sql
select * from gold.kpi_summary
where kpi_name = 'CASA Ratio' and grain = 'OVERALL';
```

## Data quality tests

38 tests, all passing.

**Generic tests** (in the `schema.yml` files):
- `unique` and `not_null` on all primary keys
- `relationships` between account, customer, branch, product, card and transactions
- `accepted_values` for `schm_type`, `acct_cls_flg`, `card_type` and `tran_direction`

**Singular tests** (in `tests/`):
- `assert_no_negative_non_loan_balance`: only loan accounts may have negative balances
- `assert_casa_ratio_between_0_and_1`: the CASA ratio must be a valid ratio

## Verified results

| Check | Result |
|---|---|
| `dbt build` | `PASS=57 WARN=0 ERROR=0` |
| `dbt test` | `PASS=38 ERROR=0` |
| Merge demo (`stg_account`) | `MERGE 3` on the first run, `MERGE 0` on the next |
| Append demo (`stg_hist_transactional`) | One new transaction appended |
| `dim_customer` / `dim_branch` / `dim_product` / `dim_card` | 50 / 30 / 15 / 60 rows |
| `dim_account` / `fct_account_balance` | 151 rows each (150 plus the demo account) |
| `fct_transactions` | 401 rows (400 plus the demo transaction) |
| **CASA Ratio (overall)** | **0.5186 (51.86%)** |

The row counts above include the demo rows added in Bronze: account `AC000151` and transaction `TXN0000401`. A clean load of `insert.sql` gives 150 accounts and 400 transactions.

## Assumptions and design decisions

- **TD (term deposit) = FD + RD.** The data has scheme types `SA`, `CA`, `FD`, `RD` and `LD`, and no `TD`. Change the `product_group` logic in `dim_product` if TD should mean FD only.
- **Loans (`LD`) have negative balances** and are excluded from the CASA ratio.
- **Balance KPIs use open accounts only** (`acct_cls_flg = 'N'`) and NPR-converted amounts.
- **Currency conversion** uses `seeds/fx_rates.csv`. The rates are illustrative and should be replaced for real reporting.
- **Transaction direction** is derived from `tran_particular`. Mobile Banking Transfer is treated as a debit (outward).
- **Data quirks are flagged, not dropped.** Some phone numbers do not have 10 digits (`is_valid_phone`), and some cards are already expired (`is_expired`). Debit cards have a NULL `closing_balance` by design.
- **`lchg_time` is identical for all rows at load time**, so the incremental merge only shows activity after some rows are updated.
- **Silver views and Gold tables.** Staging models are views (except the two incremental ones). Marts are tables for reporting speed.

## Troubleshooting

| Problem | Cause and fix |
|---|---|
| `dbt run` says "does not match any enabled nodes" | The `models` folder is outside the folder with `dbt_project.yml`. Move it inside. |
| `function round(double precision, integer) does not exist` | The seed's decimal column is read as a float. The fact models cast to `numeric` before `round()`. |
| `stg_account` shows more rows than Bronze | Duplicate rows from earlier runs. Rebuild with `dbt run -s stg_account --full-refresh`. |
| `MERGE 0` after changing Bronze | The changed rows need a newer `lchg_time` than the current maximum in Silver. |
| `dbt docs generate` fails with "similar database identifiers" | Another schema exists whose name differs from `bronze` only by capital letters. Use `dbt docs generate --empty-catalog`, or keep this project in its own database. |
| Merge syntax error | PostgreSQL older than 15. Use `incremental_strategy='delete+insert'` in `stg_account`. |

## Author

Taweshal Dev Thakur