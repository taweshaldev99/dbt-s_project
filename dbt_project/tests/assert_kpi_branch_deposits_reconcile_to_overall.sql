with deposit_kpis as (
    select
        grain,
        grain_value,
        kpi_value
    from {{ ref('kpi_account') }}
    where kpi_code = 'TOTAL_DEPOSITS'
),

totals as (
    select
        count(*) filter (
            where grain = 'OVERALL'
        ) as overall_row_count,

        count(*) filter (
            where grain = 'BRANCH'
        ) as branch_row_count,

        count(*) filter (
            where grain in ('BRANCH', 'OVERALL')
              and kpi_value is null
        ) as null_value_count,

        sum(kpi_value) filter (
            where grain = 'BRANCH'
        ) as branch_total,

        max(kpi_value) filter (
            where grain = 'OVERALL'
        ) as overall_total

    from deposit_kpis
)

select
    overall_row_count,
    branch_row_count,
    null_value_count,
    branch_total,
    overall_total,
    branch_total - overall_total as difference

from totals

where overall_row_count <> 1
   or null_value_count > 0
   or (
       branch_row_count = 0
       and overall_total is distinct from 0
   )
   or abs(coalesce(branch_total, 0) - overall_total) > 0.01