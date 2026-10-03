with bal as (
    select
        b.account_id, b.cust_id,
        br.province, br.branch_name,
        p.product_category, p.product_group,
        b.is_closed, b.balance_npr
    from {{ ref('fct_account_balance') }} b
    join {{ ref('dim_branch') }}  br on br.branch_id  = b.branch_id
    join {{ ref('dim_product') }} p  on p.product_id  = b.product_id
),

geo as (
    select
        case when branch_name is not null then 'BRANCH'
             when province    is not null then 'PROVINCE'
             else 'OVERALL' end                    as grain,
        coalesce(branch_name, province, 'ALL')     as grain_value,
        sum(case when product_group = 'CASA'         then balance_npr      else 0 end) as casa_amt,
        sum(case when product_group = 'TERM_DEPOSIT' then balance_npr      else 0 end) as td_amt,
        sum(case when product_group = 'LOAN'         then abs(balance_npr) else 0 end) as loan_amt,
        count(*)                                                                       as active_accounts
    from bal
    where not is_closed
    group by rollup (province, branch_name)
),

by_product as (
    select
        product_category,
        avg(balance_npr) filter (where product_group in ('CASA', 'TERM_DEPOSIT') and not is_closed)
            as avg_deposit_balance,
        avg(case when is_closed then 1.0 else 0.0 end) as closure_rate
    from bal
    group by product_category
)

select 'CASA_RATIO' as kpi_code, grain, grain_value,
       (casa_amt / nullif(casa_amt + td_amt, 0))::numeric as kpi_value from geo
union all
select 'TOTAL_DEPOSITS', grain, grain_value, (casa_amt + td_amt)::numeric from geo
union all
select 'LOAN_PORTFOLIO', grain, grain_value, loan_amt::numeric from geo
union all
select 'LOAN_TO_DEPOSIT_RATIO', grain, grain_value,
       (loan_amt / nullif(casa_amt + td_amt, 0))::numeric from geo
union all
select 'ACTIVE_ACCOUNTS', grain, grain_value, active_accounts::numeric from geo
union all
select 'AVG_DEPOSIT_BALANCE', 'PRODUCT_CATEGORY', product_category, avg_deposit_balance::numeric
from by_product where avg_deposit_balance is not null
union all
select 'ACCOUNT_CLOSURE_RATE', 'PRODUCT_CATEGORY', product_category, closure_rate::numeric
from by_product
union all
select 'ACCOUNTS_PER_CUSTOMER', 'OVERALL', 'ALL',
       (count(*)::numeric / count(distinct cust_id))
from bal where not is_closed
union all
select 'CARD_PENETRATION', 'OVERALL', 'ALL',
       (count(distinct c.account_id)::numeric / count(distinct b.account_id))
from {{ ref('fct_account_balance') }} b
left join {{ ref('dim_card') }} c on c.account_id = b.account_id
where not b.is_closed