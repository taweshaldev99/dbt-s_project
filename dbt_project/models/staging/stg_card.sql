with src as (
    select * from {{ source('bronze', 'card') }}
),
dedup as (
    select *, row_number() over (partition by card_number order by card_number) as rn
    from src
),
cleaned as (
    select
        trim(card_number)                      as card_number,
        upper(trim(account_id))                as account_id,
        coalesce(balance, 0)::numeric(15,2)    as card_balance,
        upper(trim(card_type))                 as card_type,
        closing_balance::numeric(15,2)         as closing_balance,
        card_expiry_date::date                 as card_expiry_date
    from dedup
    where rn = 1
)
select
    c.*,
    a.cust_id,
    (c.card_expiry_date < current_date) as is_expired
from cleaned c
inner join {{ ref('stg_account') }} a on a.account_id = c.account_id
where c.card_type in ('DEBIT', 'CREDIT')