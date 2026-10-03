with normalized_source as (
    select
        nullif(upper(trim(account_id)), '') as account_id,
        upper(trim(schm_type)) as schm_type,
        coalesce(account_balance, 0)::numeric(15, 2)
            as account_balance,
        lchg_time::timestamp as lchg_time

    from {{ source('bronze', 'account') }}
),

ranked_source as (
    select
        *,
        row_number() over (
            partition by account_id
            order by lchg_time desc nulls last
        ) as rn

    from normalized_source
),

eligible_source as (
    select account_id

    from ranked_source

    where rn = 1
      and account_id is not null
      and (
          schm_type = 'LD'
          or account_balance >= 0
      )
)

select
    b.account_id as missing_account_id

from eligible_source b

left join {{ ref('stg_account') }} s
    on s.account_id = b.account_id

where s.account_id is null