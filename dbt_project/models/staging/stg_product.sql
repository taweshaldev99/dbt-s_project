with src as (
    select * from {{ source('bronze', 'product') }}
),
dedup as (
    select *, row_number() over (partition by product_id order by product_id) as rn
    from src
)
select
    upper(trim(product_id))     as product_id,
    upper(trim(schm_type))      as schm_type,
    upper(trim(schm_code))      as schm_code,
    initcap(trim(product_desc)) as product_desc
from dedup
where rn = 1
  and product_id is not null
  and upper(trim(schm_type)) in ('SA', 'CA', 'FD', 'RD', 'LD')