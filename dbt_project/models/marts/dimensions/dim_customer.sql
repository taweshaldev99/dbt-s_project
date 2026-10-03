select
    cust_id, name, address, phone_number, postal_code,
    country, email, occupation, education, nationality,
    is_valid_phone, is_valid_email
from {{ ref('stg_customer') }}