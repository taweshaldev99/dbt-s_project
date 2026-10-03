select
    d.kpi_name,
    d.business_definition,
    d.formula,
    d.aggregation_grouping,
    r.grain,
    r.grain_value,
    round(r.kpi_value, 4) as kpi_value
from (
    select * from {{ ref('kpi_account') }}
    union all
    select * from {{ ref('kpi_transactions') }}
) r
join {{ ref('kpi_definitions') }} d using (kpi_code)