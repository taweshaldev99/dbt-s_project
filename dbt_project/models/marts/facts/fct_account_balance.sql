select
    a.account_id,
    a.cust_id,
    a.branch_id,
    a.product_id,
    a.schm_type,
    a.acct_crncy_code,
    a.account_balance,
    a.lien_amt,

    round(
        (a.account_balance * fx.rate_to_npr)::numeric,
        2
    ) as balance_npr,

    a.is_closed,
    a.lchg_time

from {{ ref('stg_account') }} a

left join {{ ref('fx_rates') }} fx
    on fx.currency_code = a.acct_crncy_code