with src as (
    select * from {{ source('bronze', 'branch') }}
),
dedup as (
    select *, row_number() over (partition by branch_id order by branch_id) as rn
    from src
)
select
    upper(trim(branch_id))        as branch_id,
    initcap(trim(province))       as province,
    initcap(trim(cluster_name))   as cluster_name,
    initcap(trim(city_name))      as city_name,
    initcap(trim(branch_name))    as branch_name,
    (branch_name ilike '%main%')  as is_main_branch
from dedup
where rn = 1
  and branch_id is not null