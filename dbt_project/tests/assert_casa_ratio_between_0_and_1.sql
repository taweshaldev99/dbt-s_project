select * from {{ ref('kpi_summary') }}
where kpi_name = 'CASA Ratio' and (kpi_value < 0 or kpi_value > 1)