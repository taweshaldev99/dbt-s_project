{{ config(
    materialized = 'incremental',
    incremental_strategy = 'append'
) }}

with src as (
    select *
    from {{ source('bronze', 'hist_transactional') }}

    {% if is_incremental() %}
    where created_date >= (
        select
            coalesce(
                max(created_date),
                timestamp '1900-01-01'
            ) - interval '3 days'
        from {{ this }}
    )
    {% endif %}
),

normalized as (
    select
        nullif(upper(trim(tran_id)), '') as tran_id,
        nullif(upper(trim(account_id)), '') as account_id,
        nullif(upper(trim(branch_id)), '') as branch_id,
        coalesce(tran_amount, 0)::numeric(15, 2) as tran_amount,
        upper(trim(coalesce(tran_crncy, 'NPR'))) as tran_crncy,
        tran_date::date as tran_date,
        trim(tran_particular) as tran_particular,
        trim(tran_remarks) as tran_remarks,
        created_date::timestamp as created_date,
        modified_date::timestamp as modified_date
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by tran_id
            order by
                modified_date desc nulls last,
                created_date desc nulls last
        ) as rn
    from normalized
),

cleaned as (
    select
        tran_id,
        account_id,
        branch_id,
        tran_amount,
        tran_crncy,
        tran_date,
        tran_particular,
        tran_remarks,
        created_date,
        modified_date
    from dedup
    where rn = 1
      and tran_id is not null
)

select
    c.*,

    case
        when c.tran_particular in (
            'Cash Deposit',
            'Cheque Deposit',
            'Fund Transfer - Inward',
            'Remittance Credit',
            'Interest Credit',
            'Salary Credit'
        ) then 'CREDIT'

        when c.tran_particular in (
            'Cash Withdrawal',
            'ATM Withdrawal',
            'Cheque Withdrawal',
            'Fund Transfer - Outward',
            'Mobile Banking Transfer',
            'Standing Instruction Debit',
            'Utility Bill Payment',
            'Loan EMI Payment',
            'Service Charge Debit',
            'POS Purchase'
        ) then 'DEBIT'

        else 'OTHER'
    end as tran_direction,

    (c.modified_date > c.created_date) as is_modified

from cleaned c

inner join {{ ref('stg_account') }} a
    on a.account_id = c.account_id

where c.tran_date is not null
  and c.tran_amount >= 0

{% if is_incremental() %}
  and not exists (
      select 1
      from {{ this }} existing
      where existing.tran_id = c.tran_id
  )
{% endif %}