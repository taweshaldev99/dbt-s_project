with normalized_source as (
    select
        nullif(upper(trim(tran_id)), '') as tran_id,
        nullif(upper(trim(account_id)), '') as account_id,
        coalesce(tran_amount, 0)::numeric(15, 2) as tran_amount,
        tran_date::date as tran_date,
        created_date::timestamp as created_date,
        modified_date::timestamp as modified_date

    from {{ source('bronze', 'hist_transactional') }}
),

ranked_source as (
    select
        *,
        row_number() over (
            partition by tran_id
            order by
                modified_date desc nulls last,
                created_date desc nulls last
        ) as rn

    from normalized_source
),

eligible_source as (
    select
        t.tran_id,
        t.account_id,
        t.created_date

    from ranked_source t

    inner join {{ ref('stg_account') }} a
        on a.account_id = t.account_id

    where t.rn = 1
      and t.tran_id is not null
      and t.tran_date is not null
      and t.tran_amount >= 0
)

select
    b.tran_id as missing_tran_id,
    b.account_id,
    b.created_date

from eligible_source b

left join {{ ref('stg_hist_transactional') }} s
    on s.tran_id = b.tran_id

where s.tran_id is null