with src as (
    select *
    from {{ source('bronze', 'card') }}
),

normalized as (
    select
        nullif(trim(card_number), '') as card_number,
        nullif(upper(trim(account_id)), '') as account_id,
        coalesce(balance, 0)::numeric(15, 2) as card_balance,
        upper(trim(card_type)) as card_type,
        closing_balance::numeric(15, 2) as closing_balance,
        card_expiry_date::date as card_expiry_date
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by card_number
            order by
                card_expiry_date desc nulls last,
                account_id,
                card_type,
                card_balance,
                closing_balance nulls last
        ) as rn
    from normalized
),

cleaned as (
    select
        card_number,
        account_id,
        card_balance,
        card_type,
        closing_balance,
        card_expiry_date
    from dedup
    where rn = 1
      and card_number is not null
)

select
    c.*,
    a.cust_id,
    (c.card_expiry_date < current_date) as is_expired

from cleaned c

inner join {{ ref('stg_account') }} a
    on a.account_id = c.account_id

where c.card_type in ('DEBIT', 'CREDIT')