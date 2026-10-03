select
    'fct_account_balance' as model_name,
    account_id::text as record_id
from {{ ref('fct_account_balance') }}
where balance_npr is null

union all

select
    'fct_transactions' as model_name,
    tran_id::text as record_id
from {{ ref('fct_transactions') }}
where tran_amount_npr is null
   or signed_amount_npr is null