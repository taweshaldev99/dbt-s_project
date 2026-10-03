with used_currencies as (
    select acct_crncy_code as currency_code
    from {{ ref('stg_account') }}

    union

    select tran_crncy as currency_code
    from {{ ref('stg_hist_transactional') }}
)

select
    u.currency_code

from used_currencies u

left join {{ ref('fx_rates') }} fx
    on fx.currency_code = u.currency_code

where fx.currency_code is null