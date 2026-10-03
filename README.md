# DBT Banking Data Engineering Project

A dbt project on PostgreSQL that builds a **Bronze → Silver → Gold** pipeline from a banking dataset (customers, branches, products, accounts, cards and historical transactions) and calculates 12 banking KPIs, including the required **CASA Ratio**.

The repository root is the dbt project (it contains `dbt_project.yml`). Run every command in this README from the repository root.

## Contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Setup](#setup)
- [Running the pipeline](#running-the-pipeline)
- [Layers in detail](#layers-in-detail)
- [Incremental models and snapshot](#incremental-models-and-snapshot)
- [Banking KPIs](#banking-kpis)
- [Data quality tests](#data-quality-tests)
- [Edge-case checks](#edge-case-checks)
- [Results and evidence](#results-and-evidence)
- [Assumptions and design decisions](#assumptions-and-design-decisions)
- [Troubleshooting](#troubleshooting)

## Architecture

```
source_data/insert.sql   (provided by the instructor, unchanged; creates tables in "public")
        │  source_data/setup_bronze.sql   (moves the six tables into "bronze")
        ▼
┌────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│  BRONZE    │ ──▶ │  SILVER         │ ──▶ │  GOLD                │
│  raw data  │     │  models/staging │     │  models/marts        │
│  6 tables  │     │  cleaned data   │     │  dims, facts, KPIs   │
└────────────┘     └─────────────────┘     └──────────────────────┘
                          │
                          ▼
                   snapshots/snap_account
```

| Layer | Schema | Purpose |
|---|---|---|
| Bronze | `bronze` | Raw source tables, loaded as-is |
| Silver | `silver` | Cleaned and standardised staging models, plus the `fx_rates` seed |
| Gold | `gold` | Dimensions, facts and KPIs for reporting |
| Snapshots | `snapshots` | Historical versions of account records |

Source relationships: `customer ── account ──┬── product / branch / card / hist_transactional`

## Repository layout

```
.
├── README.md
├── requirements.txt
├── profiles.yml.example          # connection template (the real profiles.yml is git-ignored)
├── dbt_project.yml
├── .gitignore
├── source_data/
│   ├── insert.sql                # provided by the instructor, used unchanged
│   ├── insert_to_postgres.py     # provided by the instructor, used unchanged (loads into "public")
│   └── setup_bronze.sql          # added: moves the six loaded tables from "public" to "bronze"
├── macros/
│   └── generate_schema_name.sql  # plain schema names: silver, gold
├── seeds/
│   ├── fx_rates.csv              # exchange rates to NPR
│   └── schema.yml
├── models/
│   ├── staging/                  # Silver
│   │   ├── sources.yml
│   │   ├── schema.yml
│   │   ├── stg_customer.sql
│   │   ├── stg_branch.sql
│   │   ├── stg_product.sql
│   │   ├── stg_account.sql              # incremental, merge
│   │   ├── stg_card.sql
│   │   └── stg_hist_transactional.sql   # incremental, append
│   └── marts/                    # Gold
│       ├── schema.yml
│       ├── dimensions/           # dim_customer, dim_branch, dim_product, dim_account, dim_card
│       ├── facts/                # fct_account_balance, fct_transactions
│       └── kpis/                 # kpi_definitions, kpi_account, kpi_transactions, kpi_summary
├── snapshots/
│   └── snap_account.sql
├── tests/                        # 11 singular tests (see Data quality tests)
└── docs/
    └── evidence/
        └── README.md             # checklist of logs and screenshots to save
```

> dbt project names cannot contain hyphens, so the internal name is `dbt_project`. `dbt-project` is the name of the repository.

## Setup

### 1. Prerequisites
- Python 3.9 or newer
- PostgreSQL. The `merge` incremental strategy needs PostgreSQL 15 or newer.

### 2. Install dbt
```bash
python -m venv proj
proj\Scripts\activate          # Windows
# source proj/bin/activate     # macOS / Linux
pip install -r requirements.txt
```

### 3. Configure the connection
Copy `profiles.yml.example` to `~/.dbt/profiles.yml` (Windows: `C:\Users\<you>\.dbt\profiles.yml`) and fill in your credentials. You may instead save it as `profiles.yml` in the repository root: dbt checks the current folder first, and that file is git-ignored. Never commit it.

```bash
dbt debug          # expect: All checks passed!
```

### 4. Load the Bronze data
`source_data/insert.sql` and `source_data/insert_to_postgres.py` were provided with the assignment and are used **unchanged**. The provided loader creates the six tables in the `public` schema, while the dbt project reads them from `bronze`. Loading is therefore two steps, and both files you were given stay untouched.

**Step 4a: load with the provided loader**
```powershell
# PowerShell: use the same database as in profiles.yml
$env:PGHOST="localhost"; $env:PGPORT="5432"; $env:PGDATABASE="<db>"
$env:PGUSER="<user>"; $env:PGPASSWORD="<password>"
python source_data/insert_to_postgres.py --drop
```
Expected: six tables created and loaded in `public` (50, 30, 15, 150, 60 and 400 rows).

**Step 4b: move the tables into `bronze`**
```bash
psql -h localhost -U <user> -d <db> -f source_data/setup_bronze.sql
```
(or open `source_data/setup_bronze.sql` in SQLTools or pgAdmin and run the whole file). It creates the `bronze` schema and runs `ALTER TABLE ... SET SCHEMA bronze` for each table. Foreign keys and constraints move with the tables. It is safe to run twice: tables already in `bronze` are left alone.

**Alternative without the move step.** `psql` can load the provided `insert.sql` straight into `bronze` through a connection option, again without editing the file:
```powershell
psql -h localhost -U <user> -d <db> -c "CREATE SCHEMA IF NOT EXISTS bronze"
$env:PGOPTIONS="-c search_path=bronze"
psql -h localhost -U <user> -d <db> -f source_data/insert.sql
```

**Reloading from scratch.** The provided loader's `--drop` only drops the `public` copies. To start over, run `DROP SCHEMA bronze CASCADE;` first, then repeat 4a and 4b. If you run the provided loader a second time while `bronze` already has the tables, `setup_bronze.sql` stops with a "both public.x and bronze.x exist" error and moves nothing.

**Check the result**
```sql
select 'customer' as table_name, count(*) as row_count from bronze.customer union all
select 'branch', count(*) from bronze.branch union all
select 'product', count(*) from bronze.product union all
select 'account', count(*) from bronze.account union all
select 'card', count(*) from bronze.card union all
select 'hist_transactional', count(*) from bronze.hist_transactional;

-- should return 0: nothing left behind in public
select count(*) from information_schema.tables
where table_schema = 'public'
  and table_name in ('customer','branch','product','account','card','hist_transactional');
```

## Running the pipeline

```bash
dbt seed                 # load fx_rates
dbt run -s staging       # Silver
dbt snapshot             # baseline snapshot
dbt run -s marts         # Gold
dbt test                 # data quality tests
```
Or everything in dependency order:
```bash
dbt build
```
A clean `dbt build` runs 77 nodes: 1 seed, 17 models, 1 snapshot and 58 data tests.

Documentation and lineage graph:
```bash
dbt docs generate        # use --empty-catalog if another schema differs from "bronze" only by case
dbt docs serve
```
Rebuild the incremental models from scratch (needed after changing their logic):
```bash
dbt build --full-refresh
```

## Layers in detail

### Bronze
Raw tables from `insert.sql`, with no business transformation. They are declared in `models/staging/sources.yml` and read with `{{ source('bronze', '<table>') }}`.

### Silver (staging)
- IDs and codes are **normalised first** (`TRIM`, `UPPER`, empty string to NULL) and **then** de-duplicated with `ROW_NUMBER()`, so `' ac1'` and `'AC1'` are one record.
- Data type casting, `INITCAP`/`LOWER` on text, `COALESCE` null handling, date and timestamp standardisation.
- Business rules: only loans may have negative balances, valid scheme and card types, positive transaction amounts.
- Referential integrity through joins: cards and transactions must belong to an existing account.
- Derived flags: `is_closed`, `is_expired`, `is_valid_phone`, `is_valid_email`, `tran_direction`, `is_modified`.

### Gold (marts)
- **Dimensions:** `dim_customer`, `dim_branch`, `dim_product` (adds `product_category` and `product_group`), `dim_account`, `dim_card` (masked card number).
- **Facts:** `fct_account_balance` (one row per account, balance in NPR) and `fct_transactions` (one row per transaction, amount in NPR plus a signed amount: credits positive, debits negative).
- **KPIs:** see below.

## Incremental models and snapshot

### `stg_account`: incremental MERGE
- Strategy `merge`, unique key `account_id`, watermark `lchg_time` (the source system's last-change time).
- First run: full load. Later runs: only rows newer than the target's maximum `lchg_time`; changed accounts are updated and new ones inserted.
- If the target table exists but is empty, the watermark falls back to `1900-01-01`, so everything is loaded instead of nothing.

Demo (run in PostgreSQL, then `dbt run -s stg_account`):
```sql
update bronze.account set account_balance = account_balance + 50000, lchg_time = now() where account_id = 'AC000002';
update bronze.account set branch_id = 'BR001', lchg_time = now() where account_id = 'AC000004';
insert into bronze.account
  (account_id, customer_id, branch_id, account_balance, lien_amt, acct_cls_flg, product_id, schm_type, schm_code, acct_crncy_code)
values ('AC000151', 'C0001', 'BR001', 25000, 0, 'N', 'PRD001', 'SA', 'SAV001', 'NPR');
```
Expected log: `MERGE 3`. Running it again with no changes gives `MERGE 0`.

### `stg_hist_transactional`: incremental APPEND
- Strategy `append`, watermark `created_date`.
- **Late arrivals:** each run re-scans `late_arrival_days` (default 3, set in `dbt_project.yml`) behind the newest `created_date`, so rows that arrive out of order are still picked up.
- **Target-level de-duplication:** a `NOT EXISTS (... tran_id ...)` filter against the target means the re-scanned window never appends a transaction that is already there, so `tran_id` stays unique.
- Same empty-target fallback as above.
- Limits: an append model never updates a row, so a transaction modified after it was loaded is not refreshed. A row arriving later than the window is caught by the test `assert_stg_transactions_reconcile_to_bronze`; load it once with `dbt run -s stg_hist_transactional --vars '{late_arrival_days: 45}'`.

Demo:
```sql
insert into bronze.hist_transactional
values ('TXN0000401', 'AC000002', 'BR008', 15000, 'NPR', current_date,
        'Cash Deposit', 'Deposited at branch counter', now(), now());
```
Expected log: `INSERT 0 1`. Running it again gives `INSERT 0 0`.

### Snapshot: `snap_account`
Check strategy on `account_balance`, `acct_cls_flg`, `branch_id` and `product_id`, built from `stg_account`.

1. `dbt snapshot` before changing data (baseline).
2. Change accounts in Bronze, then `dbt run -s stg_account`.
3. `dbt snapshot` again.
4. Show the history:
```sql
select account_id, account_balance, branch_id, dbt_valid_from, dbt_valid_to
from snapshots.snap_account
where account_id in ('AC000002', 'AC000004', 'AC000151')
order by account_id, dbt_valid_from;
```
Each changed account has an old row with a `dbt_valid_to` timestamp and a current row where it is NULL.

## Banking KPIs

All KPIs are calculated from Gold-layer data and carry a name, business definition, formula, SQL implementation and grouping. Definitions are in `kpi_definitions`, implementations in `kpi_account` and `kpi_transactions`, and the combined output in `kpi_summary`. Ratios use `NULLIF` on the denominator, so a zero denominator gives NULL, not an error.

| # | KPI | Business definition | Formula | Grouping |
|---|---|---|---|---|
| 1 | **CASA Ratio** | Share of deposits held in current and savings accounts | (CA + SA) / (CA + SA + TD) | Branch, province, overall |
| 2 | Total Deposits | Balance of open deposit accounts | SUM(balance), CASA and term deposits | Branch, province, overall |
| 3 | Loan Portfolio | Outstanding amount on open loans | SUM(ABS(balance)), LD | Branch, province, overall |
| 4 | Loan to Deposit Ratio | Share of deposits lent out | Loan Portfolio / Total Deposits | Branch, province, overall |
| 5 | Active Accounts | Number of open accounts | COUNT(accounts), `acct_cls_flg = 'N'` | Branch, province, overall |
| 6 | Average Deposit Balance | Average balance per open deposit account | AVG(balance) | Product category |
| 7 | Account Closure Rate | Share of accounts that are closed | Closed / All accounts | Product category |
| 8 | Accounts per Customer | Average open accounts per customer | Open accounts / Distinct customers | Overall |
| 9 | Card Penetration | Share of open accounts with a card | Accounts with a card / Open accounts | Overall |
| 10 | Transaction Count | Number of transactions | COUNT(tran_id) | Month |
| 11 | Transaction Value | Total transaction value in NPR | SUM(tran_amount_npr) | Month |
| 12 | Net Cash Flow | Inflows minus outflows in NPR | SUM(credits) - SUM(debits) | Month |

```sql
select * from gold.kpi_summary where kpi_name = 'CASA Ratio' and grain = 'OVERALL';
```

## Data quality tests

58 data tests.

**Generic tests** (in the `schema.yml` files)
- `unique` and `not_null` on every primary key
- `relationships` between account, customer, branch, product, card and transactions
- `accepted_values` for scheme type, close flag, card type and transaction direction
- **FX coverage:** `relationships` from account and transaction currencies to `fx_rates`, plus `not_null` on `balance_npr`, `tran_amount_npr` and `signed_amount_npr`
- `unique` and `not_null` on `fx_rates`

**Singular tests** (in `tests/`)

| Test | Checks | Severity |
|---|---|---|
| `assert_no_negative_non_loan_balance` | Only loans have negative balances | error |
| `assert_casa_ratio_between_0_and_1` | CASA ratio is a valid ratio | error |
| `assert_stg_account_reconciles_to_bronze` | Every valid Bronze account is in Silver | error |
| `assert_stg_transactions_reconcile_to_bronze` | No Bronze transaction is lost by the incremental watermark | error |
| `assert_fx_rates_positive` | Exchange rates are greater than 0 | error |
| `assert_no_future_transactions` | No transaction is dated in the future | error |
| `assert_kpi_branch_deposits_reconcile_to_overall` | Branch deposits add up to the overall figure | error |
| `assert_all_twelve_kpis_present` | `kpi_summary` contains all 12 KPIs | error |
| `assert_account_scheme_matches_product` | Account and product scheme types agree | warn |
| `assert_modified_not_before_created` | `modified_date` is not before `created_date` | warn |
| `assert_credit_cards_have_closing_balance` | Credit cards have a closing balance | warn |

## Edge-case checks

These are the failure modes the models are built to handle. Each can be reproduced and its log saved under `docs/evidence/`.

| Scenario | How to trigger | Expected result |
|---|---|---|
| Empty target | `truncate silver.stg_account; truncate silver.stg_hist_transactional;` then `dbt run -s stg_account stg_hist_transactional` | Full reload (`MERGE 150`, `INSERT 0 400`), not zero rows |
| Late arrival inside the window | Insert a Bronze transaction with `created_date = now() - interval '36 hours'` | Appended once |
| Late arrival outside the window | Insert one with `created_date = now() - interval '30 days'` | `assert_stg_transactions_reconcile_to_bronze` fails until the window is widened |
| Modified transaction re-seen | `update bronze.hist_transactional set modified_date = now() where tran_id = 'TXN0000401'` | `INSERT 0 0`, no duplicate `tran_id` |
| Un-normalised IDs | Insert accounts `' ac000200'` and `'AC000200 '` | One Silver account, the latest version wins |
| Missing FX rate | `delete from silver.fx_rates where currency_code = 'USD'`, then rebuild the facts and run `dbt test` | `balance_npr` is NULL and the FX tests fail; restore with `dbt seed` |
| Zero denominators | Close every account in Bronze, then rebuild Silver and Gold | The four ratio KPIs are NULL, no division error |

## Results and evidence

`dbt build` on a clean load finishes with every node passing. Row counts for the provided dataset: `dim_customer` 50, `dim_branch` 30, `dim_product` 15, `dim_card` 60, `stg_account` and `fct_account_balance` 150, `fct_transactions` 400. After the demo inserts above they become 151 accounts and 401 transactions.

CASA Ratio (overall), measured on the author's database after the demo changes: **0.5186**.

Logs and screenshots for each step are listed in [`docs/evidence/README.md`](docs/evidence/README.md).

## Assumptions and design decisions

- **TD (term deposit) = FD + RD.** The data has `SA`, `CA`, `FD`, `RD` and `LD` and no `TD`. Change `product_group` in `dim_product` if TD should mean FD only.
- **Loans (`LD`) have negative balances** and are excluded from the CASA ratio.
- **Balance KPIs use open accounts only** and NPR-converted amounts.
- **FX rates** come from `seeds/fx_rates.csv` and are illustrative. A currency without a rate is **not** silently treated as 1: the converted amount is NULL and the FX tests fail.
- **Transaction direction** is derived from `tran_particular`; Mobile Banking Transfer counts as a debit.
- **Data quirks are flagged, not dropped:** phone numbers that are not 10 digits (`is_valid_phone`), expired cards (`is_expired`), debit cards with no closing balance.
- **`lchg_time` is identical for every row at load time**, so the merge only shows activity after rows are updated.
- **Silver views, Gold tables.** Staging models are views (except the two incremental ones) and marts are tables.

## Troubleshooting

| Problem | Cause and fix |
|---|---|
| dbt says `relation "bronze.account" does not exist` | The provided loader puts the tables in `public`. Run `source_data/setup_bronze.sql` (step 4b). |
| `setup_bronze.sql` fails with "both public.x and bronze.x exist" | The provided loader was run again after the move. Run `DROP SCHEMA bronze CASCADE;`, reload with the loader, then run `setup_bronze.sql` again. |
| `dbt run` says "does not match any enabled nodes" | `models/` is outside the folder that holds `dbt_project.yml`. |
| `function round(double precision, integer) does not exist` | Seed decimals were read as floats. `dbt_project.yml` types the seed as `numeric`; run `dbt seed --full-refresh`. |
| An incremental model has duplicate or missing rows after a logic change | Rebuild it: `dbt build --full-refresh`. |
| `MERGE 0` after changing Bronze | The changed rows need a `lchg_time` newer than the target's maximum. |
| `dbt docs generate` fails with "similar database identifiers" | Another schema differs from `bronze` only by capitalisation. Use `--empty-catalog` or a separate database. |
| Merge syntax error | PostgreSQL older than 15. Use `incremental_strategy='delete+insert'` in `stg_account`. |

## Author

Taweshal Dev Thakur