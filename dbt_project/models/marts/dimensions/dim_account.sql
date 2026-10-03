select
    account_id, cust_id, branch_id, product_id,
    schm_type, schm_code, acct_crncy_code, acct_cls_flg,
    case when acct_cls_flg = 'Y' then 'CLOSED' else 'ACTIVE' end as account_status
from {{ ref('stg_account') }}