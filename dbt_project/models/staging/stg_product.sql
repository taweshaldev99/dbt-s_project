with src as (
    select *
    from {{ source('bronze', 'product') }}
),

normalized as (
    select
        nullif(upper(trim(product_id)), '') as product_id,
        upper(trim(schm_type)) as schm_type,
        upper(trim(schm_code)) as schm_code,
        initcap(trim(product_desc)) as product_desc
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by product_id
            order by
                schm_type nulls last,
                schm_code nulls last,
                product_desc nulls last
        ) as rn
    from normalized
)

select
    product_id,
    schm_type,
    schm_code,
    product_desc

from dedup

where rn = 1
  and product_id is not null
  and schm_type in ('SA', 'CA', 'FD', 'RD', 'LD')