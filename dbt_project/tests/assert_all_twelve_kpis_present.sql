with expected_kpis(kpi_code) as (
    values
        ('CASA_RATIO'),
        ('TOTAL_DEPOSITS'),
        ('LOAN_PORTFOLIO'),
        ('LOAN_TO_DEPOSIT_RATIO'),
        ('ACTIVE_ACCOUNTS'),
        ('AVG_DEPOSIT_BALANCE'),
        ('ACCOUNT_CLOSURE_RATE'),
        ('ACCOUNTS_PER_CUSTOMER'),
        ('CARD_PENETRATION'),
        ('TXN_COUNT'),
        ('TXN_VALUE'),
        ('NET_CASH_FLOW')
),

actual_kpis as (
    select distinct kpi_code
    from {{ ref('kpi_account') }}

    union

    select distinct kpi_code
    from {{ ref('kpi_transactions') }}
)

select e.kpi_code as missing_kpi_code
from expected_kpis e
left join actual_kpis a
    on a.kpi_code = e.kpi_code
where a.kpi_code is null