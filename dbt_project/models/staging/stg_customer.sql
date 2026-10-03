with src as (
    select *
    from {{ source('bronze', 'customer') }}
),

normalized as (
    select
        nullif(upper(trim(cust_id)), '') as cust_id,
        initcap(trim(name)) as name,
        trim(address) as address,
        regexp_replace(
            trim(phone_number),
            '[^0-9]',
            '',
            'g'
        ) as phone_number,
        trim(postal_code) as postal_code,
        initcap(trim(coalesce(country, 'Unknown'))) as country,
        lower(trim(email)) as email,
        initcap(trim(father_name)) as father_name,
        initcap(trim(mother_name)) as mother_name,
        initcap(trim(coalesce(occupation, 'Unknown'))) as occupation,
        trim(coalesce(education, 'Unknown')) as education,
        initcap(trim(coalesce(nationality, 'Unknown'))) as nationality
    from src
),

dedup as (
    select
        *,
        row_number() over (
            partition by cust_id
            order by
                name nulls last,
                email nulls last,
                phone_number nulls last,
                address nulls last,
                postal_code nulls last,
                country,
                father_name nulls last,
                mother_name nulls last,
                occupation,
                education,
                nationality
        ) as rn
    from normalized
)

select
    cust_id,
    name,
    address,
    phone_number,
    postal_code,
    country,
    email,
    father_name,
    mother_name,
    occupation,
    education,
    nationality,
    (length(phone_number) = 10) as is_valid_phone,
    (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') as is_valid_email

from dedup

where rn = 1
  and cust_id is not null
  and name is not null