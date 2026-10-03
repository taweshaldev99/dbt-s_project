with src as (
    select *
    from {{ source('bronze', 'branch') }}
),

normalized as (
    select
        nullif(upper(trim(branch_id)), '') as branch_id,
        initcap(trim(province)) as province,
        initcap(trim(cluster_name)) as cluster_name,
        initcap(trim(city_name)) as city_name,
        initcap(trim(branch_name)) as branch_name
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by branch_id
            order by
                branch_name nulls last,
                province nulls last,
                cluster_name nulls last,
                city_name nulls last
        ) as rn
    from normalized
)

select
    branch_id,
    province,
    cluster_name,
    city_name,
    branch_name,
    (branch_name ilike '%main%') as is_main_branch

from dedup

where rn = 1
  and branch_id is not null