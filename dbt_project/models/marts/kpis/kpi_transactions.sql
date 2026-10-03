with t as (
    select
        date_trunc('month', tran_date)::date as tran_month,
        tran_amount_npr,
        signed_amount_npr
    from {{ ref('fct_transactions') }}
)
select 'TXN_COUNT' as kpi_code, 'MONTH' as grain,
       to_char(tran_month, 'YYYY-MM') as grain_value,
       count(*)::numeric as kpi_value
from t group by tran_month
union all
select 'TXN_VALUE', 'MONTH', to_char(tran_month, 'YYYY-MM'), sum(tran_amount_npr)::numeric
from t group by tran_month
union all
select 'NET_CASH_FLOW', 'MONTH', to_char(tran_month, 'YYYY-MM'), sum(signed_amount_npr)::numeric
from t group by tran_month