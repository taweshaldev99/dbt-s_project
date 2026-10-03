select
    card_number,
    left(card_number, 4) || '-****-****-' || right(card_number, 4) as masked_card_number,
    account_id, cust_id, card_type, card_expiry_date, is_expired,
    case when is_expired then 'EXPIRED' else 'VALID' end as card_status
from {{ ref('stg_card') }}