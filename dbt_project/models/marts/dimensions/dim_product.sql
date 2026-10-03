select
    product_id, schm_type, schm_code, product_desc,
    case schm_type
        when 'SA' then 'Savings'
        when 'CA' then 'Current'
        when 'FD' then 'Fixed Deposit'
        when 'RD' then 'Recurring Deposit'
        when 'LD' then 'Loan'
        else 'Other'
    end as product_category,
    case
        when schm_type in ('CA', 'SA') then 'CASA'
        when schm_type in ('FD', 'RD') then 'TERM_DEPOSIT'
        when schm_type = 'LD'          then 'LOAN'
        else 'OTHER'
    end as product_group
from {{ ref('stg_product') }}