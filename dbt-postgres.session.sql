select
    tran_id,
    account_id,
    tran_amount,
    tran_direction,
    tran_amount_npr,
    signed_amount_npr
from gold.fct_transactions
where tran_id = 'TXNDEMO001';