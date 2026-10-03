select
    t.tran_id, t.account_id, a.cust_id, t.branch_id, a.product_id,
    t.tran_date, t.tran_amount, t.tran_crncy,
    round((t.tran_amount * coalesce(fx.rate_to_npr, 1))::numeric, 2) as tran_amount_npr,
    t.tran_particular, t.tran_direction,
    round(
        (case t.tran_direction when 'CREDIT' then 1 when 'DEBIT' then -1 else 0 end
         * t.tran_amount * coalesce(fx.rate_to_npr, 1))::numeric, 2
    ) as signed_amount_npr,
    t.created_date, t.modified_date
from {{ ref('stg_hist_transactional') }} t
join {{ ref('stg_account') }} a on a.account_id = t.account_id
left join {{ ref('fx_rates') }} fx on fx.currency_code = t.tran_crncy