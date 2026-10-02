{{ config(
    materialized         = 'incremental',
    incremental_strategy = 'merge',
    unique_key           = 'account_id',
    on_schema_change     = 'sync_all_columns'
) }}

with src as (
    select * from {{ source('bronze', 'account') }}
    {% if is_incremental() %}
    where lchg_time > (select max(lchg_time) from {{ this }})
    {% endif %}
),
dedup as (
    select *, row_number() over (partition by account_id order by lchg_time desc) as rn
    from src
),
cleaned as (
    select
        upper(trim(account_id))                         as account_id,
        upper(trim(customer_id))                        as cust_id,
        upper(trim(branch_id))                          as branch_id,
        upper(trim(product_id))                         as product_id,
        upper(trim(schm_type))                          as schm_type,
        upper(trim(schm_code))                          as schm_code,
        upper(trim(coalesce(acct_crncy_code, 'NPR')))   as acct_crncy_code,
        coalesce(account_balance, 0)::numeric(15,2)     as account_balance,
        coalesce(lien_amt, 0)::numeric(15,2)            as lien_amt,
        upper(trim(coalesce(acct_cls_flg, 'N')))        as acct_cls_flg,
        lchg_time::timestamp                            as lchg_time
    from dedup
    where rn = 1
)
select
    c.*,
    (c.acct_cls_flg = 'Y')            as is_closed,
    p.schm_type                       as product_schm_type,
    (c.schm_type = p.schm_type)       as is_schm_type_consistent
from cleaned c
left join {{ ref('stg_product') }} p
       on p.product_id = c.product_id
where c.account_id is not null
  and (c.schm_type = 'LD' or c.account_balance >= 0)