select
    a.account_id,
    a.product_id,
    a.schm_type as account_scheme_type,
    p.schm_type as product_scheme_type

from {{ ref('stg_account') }} a

left join {{ ref('stg_product') }} p
    on p.product_id = a.product_id

where p.product_id is null
   or a.schm_type is distinct from p.schm_type