{{ config(
    materialized = 'incremental',
    incremental_strategy = 'merge',
    unique_key = 'account_id',
    on_schema_change = 'sync_all_columns'
) }}

with src as (
    select *
    from {{ source('bronze', 'account') }}

    {% if is_incremental() %}
    where lchg_time > (
        select coalesce(
            max(lchg_time),
            timestamp '1900-01-01'
        )
        from {{ this }}
    )
    {% endif %}
),

normalized as (
    select
        nullif(upper(trim(account_id)), '') as account_id,
        nullif(upper(trim(customer_id)), '') as cust_id,
        nullif(upper(trim(branch_id)), '') as branch_id,
        nullif(upper(trim(product_id)), '') as product_id,
        upper(trim(schm_type)) as schm_type,
        upper(trim(schm_code)) as schm_code,
        upper(trim(coalesce(acct_crncy_code, 'NPR')))
            as acct_crncy_code,
        coalesce(account_balance, 0)::numeric(15, 2)
            as account_balance,
        coalesce(lien_amt, 0)::numeric(15, 2) as lien_amt,
        upper(trim(coalesce(acct_cls_flg, 'N'))) as acct_cls_flg,
        lchg_time::timestamp as lchg_time
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by account_id
            order by lchg_time desc nulls last
        ) as rn
    from normalized
),

cleaned as (
    select
        account_id,
        cust_id,
        branch_id,
        product_id,
        schm_type,
        schm_code,
        acct_crncy_code,
        account_balance,
        lien_amt,
        acct_cls_flg,
        lchg_time
    from dedup
    where rn = 1
      and account_id is not null
)

select
    c.*,
    (c.acct_cls_flg = 'Y') as is_closed,
    p.schm_type as product_schm_type,
    (c.schm_type = p.schm_type) as is_schm_type_consistent

from cleaned c

left join {{ ref('stg_product') }} p
    on p.product_id = c.product_id

where c.schm_type = 'LD'
   or c.account_balance >= 0