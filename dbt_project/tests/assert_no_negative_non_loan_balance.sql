select * from {{ ref('stg_account') }}
where schm_type <> 'LD' and account_balance < 0