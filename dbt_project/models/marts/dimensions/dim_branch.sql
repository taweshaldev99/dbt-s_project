select branch_id, province, cluster_name, city_name, branch_name, is_main_branch
from {{ ref('stg_branch') }}