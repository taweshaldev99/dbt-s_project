{% snapshot snap_account %}

{{ config(
    target_schema = 'snapshots',
    unique_key    = 'account_id',
    strategy      = 'check',
    check_cols    = ['account_balance', 'acct_cls_flg', 'branch_id', 'product_id']
) }}

select
    account_id, cust_id, branch_id, product_id, schm_type,
    account_balance, lien_amt, acct_cls_flg, acct_crncy_code, lchg_time
from {{ ref('stg_account') }}

{% endsnapshot %}