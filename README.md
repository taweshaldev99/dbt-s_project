# DBT Banking Data Engineering Project

A PostgreSQL and dbt project that transforms a banking dataset through **Bronze → Silver → Gold**, maintains account history with a dbt snapshot, and calculates **12 banking KPIs**, including CASA Ratio.

## Project layout

```text
dbt-s_project/
├── README.md
├── source_data/
│   ├── insert.sql                 # instructor-provided tables and data
│   ├── insert_to_postgres.py      # instructor-provided loader
│   └── setup_bronze.sql           # moves public tables into bronze
└── dbt_project/                  # run dbt commands from here
    ├── dbt_project.yml
    ├── requirements.txt
    ├── profiles.yml.example
    ├── models/
    │   ├── staging/               # six Silver models and sources.yml
    │   └── marts/
    │       ├── dimensions/        # five dimensions
    │       ├── facts/             # two facts
    │       └── kpis/              # definitions and calculated KPIs
    ├── seeds/fx_rates.csv
    ├── snapshots/snap_account.sql
    └── tests/                    # singular data-quality tests
```

The repository is named `dbt-s_project`. The internal dbt project name is `dbt_project`, because dbt project names cannot contain a hyphen.

| Layer | PostgreSQL schema | Contents |
|---|---|---|
| Bronze | `bronze` | Six raw tables from the instructor's SQL file |
| Silver | `silver` | Cleaned staging models and illustrative FX seed |
| Gold | `gold` | Dimensions, facts, and KPI models |
| History | `snapshots` | Versions of changed accounts |

## Requirements and setup

- Python **3.10+** and PostgreSQL **15+** (the MERGE strategy requires PostgreSQL 15+).
- A PostgreSQL database and account with permission to create schemas and tables.
- `dbt-core==1.12.5` and `dbt-postgres==1.11.0`, as pinned in `dbt_project/requirements.txt`.

From the **repository root**, create and activate an environment, then install the project requirements and the loader's PostgreSQL driver:

```powershell
python -m venv proj
.\proj\Scripts\Activate.ps1
python -m pip install -r .\dbt_project\requirements.txt psycopg2-binary
```

Set the loader's connection variables to the **same database** configured for dbt. These are PowerShell examples; replace the bracketed values:

```powershell
$env:PGHOST = 'localhost'
$env:PGPORT = '5432'
$env:PGDATABASE = '<database>'
$env:PGUSER = '<user>'
$env:PGPASSWORD = '<password>'
python .\source_data\insert_to_postgres.py
```

The supplied loader creates the tables in `public`. On a fresh database, it loads **50 customers, 30 branches, 15 products, 150 accounts, 60 cards, and 400 transactions**. Do not use its `--drop` option unless you deliberately intend to reset those public tables.

Move the raw tables to `bronze`:

```powershell
psql -h localhost -U <user> -d <database> -f .\source_data\setup_bronze.sql
```

Alternatively, execute the whole `setup_bronze.sql` file in a SQL client connected to the same database. The script leaves tables that are already in `bronze` in place. If both `public` and `bronze` copies exist, it stops and asks you to resolve the duplicate rather than replacing data.

Copy `dbt_project/profiles.yml.example` into your local dbt profile configuration and enter that database's connection details. Keep real credentials out of commits. Then enter the dbt project folder:

```powershell
cd .\dbt_project
dbt debug
dbt build
```

All dbt commands below assume that the current folder is `dbt_project/`. A complete build discovers **17 models, 1 seed, 1 snapshot, and 49 data tests: 68 nodes in total**. Generate and view lineage documentation with `dbt docs generate` and `dbt docs serve`.

## Transformations

**Bronze:** The six raw tables are `customer`, `branch`, `product`, `account`, `card`, and `hist_transactional`. `models/staging/sources.yml` declares all six as dbt sources under `bronze`.

**Silver:** The six `stg_*` models standardize types, text, dates, and IDs. IDs are trimmed and normalized **before** deduplication. Invalid or unsupported values are filtered or flagged according to each model's rules. Cards and transactions join to staged accounts. Four staging models are views; accounts and transactions are incremental tables.

**Gold:** `dim_customer`, `dim_branch`, `dim_product`, `dim_account`, and `dim_card` provide descriptive data. `fct_account_balance` and `fct_transactions` contain measures, with NPR conversions from the `fx_rates` seed. A missing rate yields a NULL converted amount and is caught by tests; it is not silently treated as 1. The rates in the seed are illustrative, not live market rates.

## Incremental models and account history

### Account MERGE

`stg_account` uses `incremental_strategy='merge'`, `account_id` as its unique key, and `lchg_time` as its watermark. A new or changed Bronze row must have `lchg_time` **later than the maximum timestamp already staged**. The initial run loads all eligible rows; an empty existing target falls back to a `1900-01-01` timestamp.

An account with an older or equal change timestamp may be missed; the account reconciliation test checks presence of eligible account IDs, not whether every attribute matches the source. After a deliberate change to the transformation logic, rebuild the incremental model with `dbt run --select stg_account --full-refresh`, then rebuild dependent views and marts.

### Transaction APPEND

`stg_hist_transactional` uses `incremental_strategy='append'`. Each incremental run rechecks records whose `created_date` is within **three days before the highest staged `created_date`**. It normalizes and deduplicates IDs in that batch, then excludes IDs already in the target. A rerun without new records should insert zero rows.

The three-day lookback is hard-coded in the model. A record arriving outside that window is detected by `assert_stg_transactions_reconcile_to_bronze`; it requires a deliberate backfill, such as `dbt run --select stg_hist_transactional --full-refresh` followed by rebuilding dependent marts. APPEND does **not** update a transaction already staged if its source row later changes.

### Snapshot

`snap_account` uses dbt's check strategy on account balance, closure flag, branch, and product. Capture a baseline with `dbt snapshot --select snap_account`, change a Bronze account and advance its `lchg_time`, run `dbt run --select stg_account`, then run the snapshot again. Inspect the history with:

```sql
select account_id, account_balance, dbt_valid_from, dbt_valid_to
from snapshots.snap_account
where account_id = 'AC000002'
order by dbt_valid_from;
```

A prior version has a populated `dbt_valid_to`; the current version has `dbt_valid_to IS NULL`. Existing versions are preserved when later changes are captured.

## Banking KPIs

`kpi_definitions` stores names, business definitions, formulas, and grouping. `kpi_account` and `kpi_transactions` calculate the values from Gold facts and dimensions; `kpi_summary` joins definitions to results. Ratio denominators use `NULLIF` so zero denominators return NULL.

| KPI | Calculation | Grouping |
|---|---|---|
| CASA Ratio | `(CA + SA) / (CA + SA + TD)` by deposit balance | Branch, province, overall |
| Total Deposits | Sum of open CASA and term deposit balances | Branch, province, overall |
| Loan Portfolio | Sum of absolute open loan balances | Branch, province, overall |
| Loan to Deposit Ratio | Loan Portfolio / Total Deposits | Branch, province, overall |
| Active Accounts | Count of open accounts | Branch, province, overall |
| Average Deposit Balance | Average open deposit balance | Product category |
| Account Closure Rate | Closed accounts / all accounts | Product category |
| Accounts per Customer | Open accounts / distinct customers with open accounts | Overall |
| Card Penetration | Open accounts with a card / open accounts | Overall |
| Transaction Count | Count of transactions | Month |
| Transaction Value | Sum of unsigned transaction amounts in NPR | Month |
| Net Cash Flow | Sum of signed credit and debit amounts in NPR | Month |

For this dataset, `TD` means `FD + RD`. The assumptions behind this mapping, the classification of **Mobile Banking Transfer as DEBIT**, and the illustrative FX rates should be confirmed with the instructor.

```sql
select *
from gold.kpi_summary
where kpi_name = 'CASA Ratio' and grain = 'OVERALL';
```

## Data quality and verification

The project has **49 dbt data tests**: generic tests in model and seed YAML files, plus singular tests in `dbt_project/tests/`. They cover IDs, relationships, accepted values, account and transaction presence in Silver, account/product scheme consistency, positive and complete FX coverage, non-null converted amounts, CASA bounds, branch-versus-overall deposit reconciliation, and the presence of all 12 KPIs.

Run everything in dependency order from `dbt_project/`:

```powershell
dbt build
```

The project was verified on the author's database with **68 passing nodes**. The supplied data alone contains 150 accounts and 400 transactions. The author's demonstration database already had one additional account and transaction, then a further test transaction was appended; observed Gold counts were **151 accounts and 402 transactions**. These demo counts are local database state, not rows added to the instructor's `insert.sql`.

The incremental demonstration updated account `AC000002` from **89,202.94** to **89,702.94** (`MERGE 1`). A following snapshot closed the previous version and created a new current version. A new `TXNDEMO001` Cash Deposit of **1,500.00** produced `INSERT 0 1` on the first APPEND run and `INSERT 0 0` on the second; the fact model then contained the transaction. Keep screenshots or query results from your own run if you need submission evidence. Results depend on the database state at execution time.

## Notes for reruns

- Run dbt commands from `dbt_project/`. Run `source_data` loader/setup commands from the repository root, or adjust their paths.
- Source reloads and `--full-refresh` can replace database tables. Use a dedicated assignment database when demonstrating changes.
- After rebuilding `stg_account` with `--full-refresh`, rebuild dependent models with `dbt run --select stg_account+` before running tests; a dependent view may be dropped when PostgreSQL replaces the table.
- If a transaction arrives before the three-day lookback, inspect the reconciliation test and perform a deliberate backfill. The model does not accept a `late_arrival_days` variable.
- Keep credentials and generated dbt output out of commits.

## Author

Taweshal Dev Thakur
