select *
from {{ ref('fx_rates') }}
where rate_to_npr <= 0