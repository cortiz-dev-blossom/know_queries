WITH member_account_stats AS (
    -- Calculate account statistics per member (DEPOSIT ACCOUNTS ONLY - NO LOANS)
    SELECT 
        member_number,
        COUNT(*) as total_accounts_per_member,
        COUNT(CASE WHEN date_closed IS NOT NULL THEN 1 END) as deleted_accounts_per_member,
        COUNT(CASE WHEN last_activity < DATE_SUB(CURDATE(), INTERVAL 90 DAY) OR last_activity IS NULL THEN 1 END) as inactive_accounts_per_member,
        CASE WHEN COUNT(*) > 1 THEN 'True' ELSE 'False' END as has_multiple_accounts
    FROM account 
    WHERE member_number > 0 
      AND discriminator IN ('S', 'D', 'C', 'U')  -- EXCLUDE LOANS (L)
    GROUP BY member_number
),
cu_info AS (
    -- Get credit union name
    SELECT DISTINCT credit_union_name 
    FROM credit_union_info 
    LIMIT 1
)

SELECT 
    -- Member and CU Information
    a.member_number as member_id,
    ci.credit_union_name as cu_name,
    
    -- Contact Information
    pn.phone_number AS member_phone,
    e.email1 AS member_email,
    
    CASE 
            WHEN ma.member_number IS NOT NULL THEN 'Online Application'
            WHEN a.created_by_userid IN ('88', '87', '92', '95', 'XXZ') THEN 'Automated Process'
            WHEN a.created_by_userid REGEXP '^[0-9]+$' THEN 'Staff-Assisted'
            WHEN a.created_by_userid = 'PCN' THEN 'Migration'
            ELSE 'Unknown'
    END as estimated_channel,
    
    -- Simplified Account Type Classification (DEPOSIT ACCOUNTS ONLY)
    CASE 
        -- SAVINGS (S) - Simplified to main categories
        WHEN a.discriminator = 'S' AND a.account_type = 'PSAV' THEN 'Savings'
        WHEN a.discriminator = 'S' AND a.account_type = 'SSAV' THEN 'Savings'
        WHEN a.discriminator = 'S' AND a.account_type = 'MMA' THEN 'Money Market'
        WHEN a.discriminator = 'S' AND a.account_type = 'CCO' THEN 'Share Certificate'
        WHEN a.discriminator = 'S' AND a.account_type = 'CLUB' THEN 'Club Savings'
        WHEN a.discriminator = 'S' AND a.account_type = 'HYS' THEN 'High Yield Savings'
        WHEN a.discriminator = 'S' AND a.account_type = 'YSAV' THEN 'Youth Savings'
        WHEN a.discriminator = 'S' AND a.account_type = 'SCO' THEN 'Share Certificate'
        WHEN a.discriminator = 'S' THEN 'Other Savings'
        
        -- CHECKING (D) - Simplified
        WHEN a.discriminator = 'D' AND a.account_type = 'CHK' THEN 'Checking'
        WHEN a.discriminator = 'D' THEN 'Other Checking'
        
        -- CERTIFICATES (C) - Simplified
        WHEN a.discriminator = 'C' AND a.account_type = 'CERT' THEN 'Certificate'
        WHEN a.discriminator = 'C' AND a.account_type = 'TICD' THEN 'Term Certificate'
        WHEN a.discriminator = 'C' AND a.account_type = 'RICD' THEN 'IRA Certificate'
        WHEN a.discriminator = 'C' THEN 'Other Certificate'
        
        -- SPECIAL/UNKNOWN (U)
        WHEN a.discriminator = 'U' THEN 'Special Account'
        
        ELSE CONCAT(a.discriminator, '-', a.account_type)
    END as account_type_description,
    
    -- Main Category (Discriminator explanation - DEPOSIT ACCOUNTS ONLY)
    CASE 
        WHEN a.discriminator = 'S' THEN 'SAVINGS'
        WHEN a.discriminator = 'D' THEN 'CHECKING' 
        WHEN a.discriminator = 'C' THEN 'CERTIFICATES'
        WHEN a.discriminator = 'U' THEN 'SPECIAL'
        ELSE 'OTHER'
    END as main_account_category,
    
    -- Account Dates
    a.date_opened as created_date,
    a.date_closed as deleted_date,
    
    -- Account Status
    CASE 
        WHEN a.date_closed IS NOT NULL THEN 'Deleted'
        WHEN COALESCE(a.access_control, '') IN ('B', 'R') THEN 'Blocked'
        ELSE 'Enabled'
    END as deleted_status,
    
    -- Activity Status (Last 3 months movements based on real transactions)
    CASE 
        WHEN th.account_id IS NOT NULL THEN 'Active'
        ELSE 'Inactive'
    END as active_status_last_3_months,
    
    -- Account Details
    a.account_number,
    a.current_balance,
    
    -- Member Account Statistics
    mas.total_accounts_per_member as number_of_accounts_per_member,
    mas.has_multiple_accounts,
    mas.deleted_accounts_per_member as accounts_deleted_per_member,
    mas.inactive_accounts_per_member as accounts_inactive_per_member

FROM account a
CROSS JOIN cu_info ci
LEFT JOIN member_account_stats mas ON a.member_number = mas.member_number
LEFT JOIN member_application ma on a.member_number = ma.member_number
LEFT JOIN member m ON a.member_number = m.member_number
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
LEFT JOIN (
    SELECT DISTINCT account_id 
    FROM transaction_history 
    WHERE date_actual >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    AND void_flag = 0
) th ON a.account_id = th.account_id
WHERE a.member_number > 0 
  AND a.discriminator IN ('S', 'D', 'C', 'U')  -- EXCLUDE LOANS (L)

ORDER BY 
    a.member_number,
    CASE 
        WHEN a.discriminator = 'S' THEN 1
        WHEN a.discriminator = 'D' THEN 2
        WHEN a.discriminator = 'C' THEN 3
        WHEN a.discriminator = 'U' THEN 4
        ELSE 5
    END,
    a.date_opened DESC