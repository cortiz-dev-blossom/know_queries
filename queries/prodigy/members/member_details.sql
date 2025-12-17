SELECT 
    account_id,
    account_number,
    CASE
        WHEN description IS NULL THEN ''
        ELSE description
    END AS description,
    current_balance,
    CASE
        WHEN date_closed IS NULL THEN 'Still Open'
        ELSE date_closed
    END AS date_closed,
    date_opened,
    CASE 
        WHEN date_closed IS NULL THEN 'Active'
        ELSE 'Closed'
    END as product_status,
    CASE discriminator
        WHEN 'S' THEN 'Savings'
        WHEN 'D' THEN 'Checkings'  
        WHEN 'L' THEN 'Loan'
        WHEN 'C' THEN 'Certificate'
        WHEN 'U' THEN 'Custom'
    END as product_type,
    m.member_id,
    m.member_number,
    -- Contact information
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    -- Filter columns for dashboard
    CASE WHEN m.member_number > 0 THEN 'Valid' ELSE 'Invalid' END AS member_number_is_valid,
    CASE WHEN m.inactive_flag = 'I' THEN 'Inactive Flag' ELSE 'Active Flag' END AS member_inactive_flag_status,
    -- UPDATED: Match user query logic - exclude NULL values
    CASE 
        WHEN m.all_accounts_closed = 1 THEN 'All Closed'
        WHEN m.all_accounts_closed = 0 THEN 'Has Open Accounts'
        ELSE 'Unknown/NULL'
    END AS member_accounts_status,
    m.inactive_flag AS member_inactive_flag_code,
    m.all_accounts_closed AS member_all_accounts_closed_flag,
    e.address1,
    YEAR(CURDATE()) - YEAR(e.dob) AS age,
    -- Age group calculation
    CASE 
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 0 AND 17 THEN 'A. 0-17'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 18 AND 25 THEN 'B. 18-25'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 26 AND 35 THEN 'C. 26-35'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 36 AND 45 THEN 'D. 36-45'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 46 AND 55 THEN 'E. 46-55'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 56 AND 65 THEN 'F. 56-65'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 66 AND 75 THEN 'G. 66-75'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 76 AND 85 THEN 'H. 76-85'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) > 85 THEN 'I. 85+'
        ELSE 'Unknown'
    END as age_group,
    -- Full name construction
    CASE 
        WHEN e.name_first IS NULL OR e.name_first = '[NULL]' 
        THEN CONCAT(UPPER(LEFT(e.name_last, 1)), LOWER(SUBSTRING(e.name_last, 2)))
        WHEN e.name_middle IS NOT NULL AND e.name_middle != '[NULL]' AND e.name_middle != ''
        THEN CONCAT(
            UPPER(LEFT(e.name_first, 1)), LOWER(SUBSTRING(e.name_first, 2)), ' ',
            UPPER(LEFT(e.name_middle, 1)), LOWER(SUBSTRING(e.name_middle, 2)), ' ',
            UPPER(LEFT(e.name_last, 1)), LOWER(SUBSTRING(e.name_last, 2))
        )
        ELSE CONCAT(
            UPPER(LEFT(e.name_first, 1)), LOWER(SUBSTRING(e.name_first, 2)), ' ',
            UPPER(LEFT(e.name_last, 1)), LOWER(SUBSTRING(e.name_last, 2))
        )
    END AS full_name,
    DATE(m.join_date) as join_date,
    -- Member tenure category
    CASE 
        WHEN DATEDIFF(CURDATE(), m.join_date) < 183 THEN '1. Recent (0-6 months)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 365 THEN '2. New (6-12 months)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 1095 THEN '3. Established (1-3 years)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 1825 THEN '4. Mature (3-5 years)'
        ELSE '5. Veteran (5+ years)'
    END as member_tenure_category,
    -- Member type
    CASE 
        WHEN m.member_type = 'P' THEN 'Personal'
        WHEN m.member_type = 'B' THEN 'Business'
        WHEN m.member_type = 'C' THEN 'Corporate Member'
        ELSE 'Unknown'
    END as member_type,
    -- Online banking status
    CASE 
        WHEN m.home_bank_date IS NOT NULL THEN 'Active'
        ELSE 'Inactive'
    END as online_banking_status
FROM Account a
LEFT JOIN member m ON a.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1