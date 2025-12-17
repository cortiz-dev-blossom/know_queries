WITH
member_product_counts AS (
    -- Count total products per member across all product types (same logic preserved)
    SELECT 
        member_number,
        COUNT(*) AS total_products_per_member
    FROM (
        -- Accounts (Savings, Checking, Certificates, Special) - EXCLUDING LOANS
        SELECT member_number
        FROM account 
        WHERE discriminator IN ('S', 'D', 'C', 'U')
          AND date_closed IS NULL 
          AND (access_control IS NULL OR access_control NOT IN ('B','R'))

        UNION ALL

        -- Traditional Loans (excluding credit card account types)
        SELECT a.member_number
        FROM account a 
        JOIN account_loan al ON a.account_id = al.account_id 
        WHERE a.discriminator = 'L' 
          AND a.account_type NOT IN ('CC', 'PCO', 'PCCO')
          AND a.date_closed IS NULL 
          AND a.charge_off_date IS NULL

        UNION ALL

        -- Physical Cards (Debit, ATM only - excluding physical credit cards to avoid duplication)
        SELECT member_number
        FROM eft_card_file 
        WHERE card_type IN ('D', 'DI', 'A')
          AND block_date IS NULL 
          AND expire_date >= CURDATE() 
          AND reject_code NOT IN ('34', '36', '41', '43', '07')
          AND lost_or_stolen = ' '
          AND last_pin_used_date IS NOT NULL  -- Must have been used

        UNION ALL

        -- Physical Credit Cards
        SELECT member_number
        FROM eft_card_file 
        WHERE card_type IN ('C', 'PC')
          AND block_date IS NULL 
          AND expire_date >= CURDATE() 
          AND reject_code NOT IN ('34', '36', '41', '43', '07')
          AND lost_or_stolen = ' '
          AND last_pin_used_date IS NOT NULL  -- Must have been used

        UNION ALL

        -- Credit Card Accounts
        SELECT a.member_number
        FROM account a 
        JOIN account_loan al ON a.account_id = al.account_id 
        WHERE a.discriminator = 'L' 
          AND al.credit_limit > 0
          AND a.date_closed IS NULL 
          AND a.charge_off_date IS NULL
    ) all_products
    GROUP BY member_number
),

cu_info AS (
    -- Single row: credit union name
    SELECT credit_union_name
    FROM credit_union_info 
    ORDER BY credit_union_name
    LIMIT 1
),

member_status AS (
    -- Member active status with filter columns
    -- UPDATED: all_accounts_closed <> 1 excludes NULL (151 members excluded)
    -- This gives exactly 11,790 active members matching: WHERE all_accounts_closed <> 1 AND inactive_flag <> 'I'
    SELECT 
        member_number,
        CASE 
            WHEN member_number IS NOT NULL 
             AND member_type IS NOT NULL 
             AND all_accounts_closed = 0
             AND inactive_flag <> 'I' 
            THEN 'Active'
            ELSE 'Inactive'
        END AS member_status,
        -- Filter columns for dashboard
        CASE WHEN member_number > 0 THEN 'Valid' ELSE 'Invalid' END AS member_number_is_valid,
        CASE WHEN inactive_flag = 'I' THEN 'Inactive Flag' ELSE 'Active Flag' END AS member_inactive_flag_status,
        -- UPDATED: Match user query logic - exclude NULL values
        CASE 
            WHEN all_accounts_closed = 1 THEN 'All Closed'
            WHEN all_accounts_closed = 0 THEN 'Has Open Accounts'
            ELSE 'Unknown/NULL'
        END AS member_accounts_status,
        inactive_flag AS member_inactive_flag_code,
        all_accounts_closed AS member_all_accounts_closed_flag
    FROM member
),

member_kind AS (
    -- Human-readable member_type
    SELECT 
        m.member_number,
        CASE 
            WHEN m.member_type = 'B' THEN 'Business'
            WHEN m.member_type = 'C' THEN 'Corporate'
            WHEN m.member_type = 'P' THEN 'Member'
            ELSE 'Unknown'
        END AS member_category
    FROM member m
),

recent_account_activity AS (
    -- Centralize "recent activity" for accounts (90 days, void_flag = 0)
    SELECT DISTINCT th.account_id
    FROM transaction_history th
    WHERE th.date_actual >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
      AND th.void_flag = 0
)

-- =========================
-- ACCOUNTS (non-loans)
-- =========================
SELECT 
    a.member_number AS id_member,
    a.account_number AS id_product,
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    'Accounts' AS main_category,
    CASE 
        WHEN a.discriminator = 'S' THEN 'Savings Account'
        WHEN a.discriminator = 'D' THEN 'Checking Account'
        WHEN a.discriminator = 'C' THEN 'Certificate Account'
        WHEN a.discriminator = 'U' THEN 'Other Account'
    END AS category_product,
    ci.credit_union_name AS cu_name,
    a.account_number AS product_number,
    a.date_opened AS date_opened_product,
    a.date_closed AS date_closed_product,
    mpc.total_products_per_member AS number_of_products_for_member,
    CASE 
        WHEN a.date_closed IS NULL THEN 'Active' 
        ELSE 'Inactive' 
    END AS product_is_active,
    CASE 
        WHEN ra.account_id IS NOT NULL THEN 'With Recent Activity'
        ELSE 'No Recent Activity'
    END AS recent_activity_status,
    ms.member_status AS member_status,
    'account' AS table_name_origin,
    mk.member_category,
    -- New filter columns
    ms.member_number_is_valid,
    ms.member_inactive_flag_status,
    ms.member_accounts_status,
    ms.member_inactive_flag_code,
    ms.member_all_accounts_closed_flag
FROM account a
CROSS JOIN cu_info ci
LEFT JOIN member_product_counts mpc ON a.member_number = mpc.member_number
LEFT JOIN member_status ms         ON a.member_number = ms.member_number
LEFT JOIN member_kind mk           ON mk.member_number = a.member_number
LEFT JOIN recent_account_activity ra ON ra.account_id = a.account_id
LEFT JOIN member m ON a.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
WHERE a.discriminator IN ('S', 'D', 'C', 'U')

UNION ALL

-- =========================
-- LOANS (excluding CC account types)
-- =========================
SELECT 
    a.member_number AS id_member,
    a.account_number AS id_product,
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    'Loans' AS main_category,
    'Loan' AS category_product,
    ci.credit_union_name AS cu_name,
    a.account_number AS product_number,
    a.date_opened AS date_opened_product,
    a.date_closed AS date_closed_product,
    mpc.total_products_per_member AS number_of_products_for_member,
    CASE 
        WHEN a.date_closed IS NULL AND a.charge_off_date IS NULL THEN 'Active' 
        ELSE 'Inactive' 
    END AS product_is_active,
    CASE 
        WHEN ra.account_id IS NOT NULL THEN 'With Recent Activity'
        ELSE 'No Recent Activity'
    END AS recent_activity_status,
    ms.member_status AS member_status,
    'account_loan' AS table_name_origin,
    mk.member_category,
    -- New filter columns
    ms.member_number_is_valid,
    ms.member_inactive_flag_status,
    ms.member_accounts_status,
    ms.member_inactive_flag_code,
    ms.member_all_accounts_closed_flag
FROM account a
JOIN account_loan al              ON a.account_id = al.account_id
CROSS JOIN cu_info ci
LEFT JOIN member_product_counts mpc ON a.member_number = mpc.member_number
LEFT JOIN member_status ms         ON a.member_number = ms.member_number
LEFT JOIN member_kind mk           ON mk.member_number = a.member_number
LEFT JOIN recent_account_activity ra ON ra.account_id = a.account_id
LEFT JOIN member m ON a.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
WHERE a.discriminator = 'L' 

UNION ALL

-- =========================
-- DEBIT / ATM CARDS (physical)
-- =========================
SELECT 
    c.member_number AS id_member,
    CONCAT(c.member_number, '_CARD_', c.record_number) AS id_product,
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    'Cards' AS main_category,
    CASE 
        WHEN c.card_type = 'D'  THEN 'Debit Card'
        WHEN c.card_type = 'DI' THEN 'Debit Instant Card'
        WHEN c.card_type = 'A'  THEN 'ATM Card'
        ELSE 'Other Debit Card'
    END AS category_product,
    ci.credit_union_name AS cu_name,
    CAST(c.record_number AS CHAR) AS product_number,
    c.issue_date AS date_opened_product,
    CASE 
        WHEN c.block_date IS NOT NULL THEN c.block_date
        WHEN c.expire_date < CURDATE() THEN c.expire_date 
        ELSE NULL 
    END AS date_closed_product,
    mpc.total_products_per_member AS number_of_products_for_member,
    CASE 
        WHEN c.block_date IS NULL 
         AND c.expire_date >= CURDATE() 
         AND c.reject_code = '00'
         AND c.lost_or_stolen = ' '
         AND c.last_pin_used_date IS NOT NULL
        THEN 'Active' 
        ELSE 'Inactive' 
    END AS product_is_active,
    CASE 
        WHEN c.last_pin_used_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 'With Recent Activity'
        ELSE 'No Recent Activity'
    END AS recent_activity_status,
    ms.member_status AS member_status,
    'eft_card_file_debit' AS table_name_origin,
    mk.member_category,
    -- New filter columns
    ms.member_number_is_valid,
    ms.member_inactive_flag_status,
    ms.member_accounts_status,
    ms.member_inactive_flag_code,
    ms.member_all_accounts_closed_flag
FROM eft_card_file c
CROSS JOIN cu_info ci
LEFT JOIN member_product_counts mpc ON c.member_number = mpc.member_number
LEFT JOIN member_status ms         ON c.member_number = ms.member_number
LEFT JOIN member_kind mk           ON mk.member_number = c.member_number
LEFT JOIN member m ON c.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
WHERE c.card_type IN ('D', 'DI', 'A')

UNION ALL

-- =========================
-- PHYSICAL CREDIT CARDS
-- =========================
SELECT 
    c.member_number AS id_member,
    CONCAT(c.member_number, '_CREDITCARD_', c.record_number) AS id_product,
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    'Cards' AS main_category,
    CASE 
        WHEN c.card_type = 'C'  THEN 'Credit Gold Card'
        WHEN c.card_type = 'PC' THEN 'Credit Platinum Card'
        ELSE 'Other Credit Card'
    END AS category_product,
    ci.credit_union_name AS cu_name,
    CAST(c.record_number AS CHAR) AS product_number,
    c.issue_date AS date_opened_product,
    CASE 
        WHEN c.block_date IS NOT NULL THEN c.block_date
        WHEN c.expire_date < CURDATE() THEN c.expire_date 
        ELSE NULL 
    END AS date_closed_product,
    mpc.total_products_per_member AS number_of_products_for_member,
    CASE 
        WHEN c.block_date IS NULL 
         AND c.expire_date >= CURDATE() 
         AND c.reject_code = '00'
         AND c.lost_or_stolen = ' '
         AND c.last_pin_used_date IS NOT NULL
        THEN 'Active' 
        ELSE 'Inactive'
    END AS product_is_active,
    CASE 
        WHEN c.last_pin_used_date >= DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 'With Recent Activity'
        ELSE 'No Recent Activity'
    END AS recent_activity_status,
    ms.member_status AS member_status,
    'eft_card_file_credit' AS table_name_origin,
    mk.member_category,
    -- New filter columns
    ms.member_number_is_valid,
    ms.member_inactive_flag_status,
    ms.member_accounts_status,
    ms.member_inactive_flag_code,
    ms.member_all_accounts_closed_flag
FROM eft_card_file c
CROSS JOIN cu_info ci
LEFT JOIN member_product_counts mpc ON c.member_number = mpc.member_number
LEFT JOIN member_status ms         ON c.member_number = ms.member_number
LEFT JOIN member_kind mk           ON mk.member_number = c.member_number
LEFT JOIN member m ON c.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
WHERE c.card_type IN ('C', 'PC')

UNION ALL

-- =========================
-- CREDIT CARD ACCOUNTS (credit lines)
-- =========================
SELECT 
    a.member_number AS id_member,
    CONCAT(a.account_number, '_CREDIT_ACCOUNT') AS id_product,
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    'Cards' AS main_category,
    'Credit Card Account' AS category_product,
    ci.credit_union_name AS cu_name,
    a.account_number AS product_number,
    a.date_opened AS date_opened_product,
    a.date_closed AS date_closed_product,
    mpc.total_products_per_member AS number_of_products_for_member,
    CASE 
        WHEN a.date_closed IS NULL AND a.charge_off_date IS NULL THEN 'Active' 
        ELSE 'Inactive'
    END AS product_is_active,
    CASE 
        WHEN ra.account_id IS NOT NULL THEN 'With Recent Activity'
        ELSE 'No Recent Activity'
    END AS recent_activity_status,
    ms.member_status AS member_status,
    'account_loan_credit' AS table_name_origin,
    mk.member_category,
    -- New filter columns
    ms.member_number_is_valid,
    ms.member_inactive_flag_status,
    ms.member_accounts_status,
    ms.member_inactive_flag_code,
    ms.member_all_accounts_closed_flag
FROM account a
JOIN account_loan al              ON a.account_id = al.account_id
CROSS JOIN cu_info ci
LEFT JOIN member_product_counts mpc ON a.member_number = mpc.member_number
LEFT JOIN member_status ms         ON a.member_number = ms.member_number
LEFT JOIN member_kind mk           ON mk.member_number = a.member_number
LEFT JOIN recent_account_activity ra ON ra.account_id = a.account_id
LEFT JOIN member m ON a.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
WHERE a.discriminator = 'L' 
  AND al.credit_limit > 0

ORDER BY id_member, main_category, category_product, product_is_active DESC