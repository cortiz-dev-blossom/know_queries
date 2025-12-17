WITH 
-- ALL Physical Cards from eft_card_file using pd_xmaif for accurate classification
all_physical_cards AS (
    SELECT 
        ecf.member_number as member_id,
        CAST(ecf.record_number AS CHAR) as card_id,
        CAST(RIGHT(ecf.record_number, 4) AS CHAR) as last_4_digits,
        
        -- Card Type Classification using pd_xmaif (accurate source)
        CAST(CASE 
            WHEN x.credit_card = 'Y' THEN CONCAT(x.description, ' Credit Card')
            WHEN x.debit_card = 'Y' THEN x.description
            WHEN x.atm_card = 'Y' THEN x.description
            ELSE COALESCE(x.description, 'Unknown Card')
        END AS CHAR) as card_type,
        
        -- Card Brand from pd_xmaif (definitive source)
        CAST(COALESCE(x.card_issuer, 'Unknown') AS CHAR) as card_brand,
        
        ecf.issue_date as creation_date,
        ecf.block_date as deleted_date,
        ecf.expire_date as expiration_date,
        
        -- Balance (for debit/ATM cards, use linked account balance; for credit cards, set to 0 as limit is in account_loan)
        CASE 
            WHEN x.credit_card = 'Y' THEN CAST(0 AS DECIMAL(15,2))
            ELSE COALESCE(ecf.share_acct_bal, ecf.draft_acct_bal, 0)
        END as balance_or_credit_limit,
        
        -- Credit fields (NULL for debit/ATM cards, 0 for physical credit cards)
        CAST(CASE WHEN x.credit_card = 'Y' THEN 0 ELSE NULL END AS DECIMAL(15,2)) as credit_used,
        CAST(CASE WHEN x.credit_card = 'Y' THEN 0 ELSE NULL END AS DECIMAL(15,2)) as credit_used_percentage,
        
        -- Status Analysis
        CAST(CASE 
            WHEN ecf.block_date IS NOT NULL THEN 'Blocked'
            WHEN ecf.reject_code IN ('34', '43') THEN 'Fraud Block'
            WHEN ecf.reject_code IN ('36', '41') THEN 'Lost/Stolen Block'
            WHEN ecf.reject_code = '07' THEN 'Special Handling'
            WHEN ecf.expire_date < CURDATE() THEN 'Expired'
            WHEN ecf.last_pin_used_date IS NOT NULL THEN 'Active'
            WHEN ecf.issue_date IS NOT NULL THEN 'Issued Not Used'
            ELSE 'Unknown'
        END AS CHAR) as status,
        
        -- Delinquency (N/A for debit cards)
        CAST('N/A' AS CHAR) as delinquency_bracket,
        
        -- Activation Information
        ecf.last_pin_used_date as activation_date,
        CAST(CASE WHEN ecf.last_pin_used_date IS NOT NULL THEN 'True' ELSE 'False' END AS CHAR) as is_activated,
        
        -- Fraud Incident Flag
        CAST(CASE 
            WHEN ecf.reject_code IN ('34', '43') THEN 'True'
            WHEN ecf.lost_or_stolen != ' ' AND ecf.lost_or_stolen IS NOT NULL THEN 'True'
            ELSE 'False'
        END AS CHAR) as fraud_incident,
        
        -- For activity check
        ecf.last_pin_used_date as last_activity_date,
        
        -- Card Source (dynamically determined from pd_xmaif)
        CAST(CASE 
            WHEN x.credit_card = 'Y' THEN 'Physical Credit'
            WHEN x.debit_card = 'Y' THEN 'Physical Debit'
            WHEN x.atm_card = 'Y' THEN 'Physical ATM'
            ELSE 'Physical Other'
        END AS CHAR) as card_source,
        
        -- Store raw card_type for reference
        ecf.card_type as raw_card_type,
        
        -- Contact Information
        pn.phone_number AS member_phone,
        e.email1 AS member_email
        
    FROM eft_card_file ecf
    LEFT JOIN pd_xmaif x ON ecf.card_type = x.card_type
    LEFT JOIN member m ON ecf.member_number = m.member_number
    LEFT JOIN entity e ON m.member_entity_id = e.entity_id
    LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
    WHERE x.inactive_flag = 0  -- Only active card types from pd_xmaif (matches product_overview.sql)
),

-- Credit Card Accounts from account_loan joined with account for member info
credit_card_accounts AS (
    SELECT 
        a.member_number as member_id,
        CAST(al.account_id AS CHAR) as card_id,
        CAST('****' AS CHAR) as last_4_digits,  -- Card numbers not stored in loan table
        
        CAST('Credit Account' AS CHAR) as card_type,
        CAST('Unknown' AS CHAR) as card_brand,  -- Brand info not available in loan table
        
        COALESCE(al.funded_date, a.date_opened) as creation_date,
        a.date_closed as deleted_date,
        al.credit_expiration as expiration_date,
        
        -- Credit Card Financial Information
        al.credit_limit as balance_or_credit_limit,
        a.current_balance as credit_used,
        CASE 
            WHEN al.credit_limit > 0 THEN ROUND((a.current_balance * 100.0) / al.credit_limit, 2)
            ELSE 0 
        END as credit_used_percentage,
        
        -- Status Analysis - CORRECTED to use next_payment_date for delinquency
        CAST(CASE 
            WHEN a.date_closed IS NOT NULL THEN 'Closed'
            WHEN a.charge_off_date IS NOT NULL THEN 'Charged Off'
            WHEN al.next_payment_date IS NOT NULL AND DATEDIFF(CURDATE(), al.next_payment_date) > 30 THEN 'Delinquent'
            WHEN a.current_balance > al.credit_limit THEN 'Over Limit'
            WHEN a.status = 'ACTIVE' THEN 'Active'
            WHEN a.status = 'CLOSED' THEN 'Closed'
            WHEN a.status = 'FROZEN' THEN 'Frozen'
            ELSE 'Active'
        END AS CHAR) as status,
        
        -- Delinquency Bracket in 30-day blocks - CORRECTED to use next_payment_date
        CAST(CASE 
            WHEN al.next_payment_date IS NULL THEN 'Unknown'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) <= 0 THEN 'Current'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) BETWEEN 1 AND 30 THEN '1-30 Days'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) BETWEEN 31 AND 60 THEN '31-60 Days'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) BETWEEN 61 AND 90 THEN '61-90 Days'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) BETWEEN 91 AND 120 THEN '91-120 Days'
            WHEN DATEDIFF(CURDATE(), al.next_payment_date) > 120 THEN '120+ Days'
            ELSE 'Current'
        END AS CHAR) as delinquency_bracket,
        
        -- Activation (assume funded_date or opened_date as activation for credit cards)
        COALESCE(al.funded_date, a.date_opened) as activation_date,
        CAST(CASE WHEN COALESCE(al.funded_date, a.date_opened) IS NOT NULL THEN 'True' ELSE 'False' END AS CHAR) as is_activated,
        
        -- Fraud Incident (based on charge-offs or specific indicators)
        CAST(CASE 
            WHEN a.charge_off_date IS NOT NULL THEN 'True'
            WHEN a.status = 'FRAUD' THEN 'True'
            ELSE 'False'
        END AS CHAR) as fraud_incident,
        
        -- For activity check (use last payment date)
        al.last_payment_date as last_activity_date,
        
        -- Card Source
        CAST('Credit Account' AS CHAR) as card_source,
        
        -- Contact Information
        pn.phone_number AS member_phone,
        e.email1 AS member_email
        
    FROM account_loan al
    INNER JOIN account a ON al.account_id = a.account_id
    LEFT JOIN member m ON a.member_number = m.member_number
    LEFT JOIN entity e ON m.member_entity_id = e.entity_id
    LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
    WHERE al.credit_limit > 0  -- Credit Card loans only
    AND a.discriminator = 'L'  -- Loan accounts
    AND a.member_number > 0
),

-- Member card type analysis
member_card_types AS (
    SELECT 
        member_id,
        MAX(member_phone) AS member_phone,
        MAX(member_email) AS member_email,
        CASE 
            WHEN COUNT(CASE WHEN card_source IN ('Physical Debit', 'Physical ATM') THEN 1 END) > 0 
                AND COUNT(CASE WHEN card_source IN ('Physical Credit', 'Credit Account') THEN 1 END) > 0 
            THEN 'Both'
            WHEN COUNT(CASE WHEN card_source IN ('Physical Debit', 'Physical ATM') THEN 1 END) > 0 
            THEN 'Debit Only'
            WHEN COUNT(CASE WHEN card_source IN ('Physical Credit', 'Credit Account') THEN 1 END) > 0 
            THEN 'Credit Only'
            ELSE 'Unknown'
        END as member_card_portfolio
    FROM (
        SELECT member_id, card_source, member_phone, member_email FROM all_physical_cards
        UNION ALL
        SELECT member_id, card_source, member_phone, member_email FROM credit_card_accounts
    ) all_cards
    GROUP BY member_id
)

-- Final unified result
SELECT 
    uc.member_id,
    mct.member_phone,
    mct.member_email,
    uc.card_id,
    uc.last_4_digits,
    uc.card_type,
    uc.card_brand,
    uc.creation_date,
    uc.deleted_date,
    uc.expiration_date,
    uc.balance_or_credit_limit,
    uc.credit_used,
    uc.credit_used_percentage,
    uc.status,
    uc.delinquency_bracket,
    uc.activation_date,
    uc.is_activated,
    
    -- Inactivity flag (no activity in 3 months)
    CASE 
        WHEN uc.last_activity_date IS NULL THEN 'True'
        WHEN DATEDIFF(CURDATE(), uc.last_activity_date) > 90 THEN 'True'
        ELSE 'False'
    END as inactivity_flag,
    
    uc.fraud_incident,
    uc.card_source,
    
    -- Member card portfolio type
    mct.member_card_portfolio

FROM (
    SELECT 
        member_id, card_id, last_4_digits, card_type, card_brand, 
        creation_date, deleted_date, expiration_date, 
        balance_or_credit_limit, credit_used, credit_used_percentage,
        status, delinquency_bracket, activation_date, is_activated,
        fraud_incident, last_activity_date, card_source,
        member_phone, member_email
    FROM all_physical_cards
    
    UNION ALL
    
    SELECT 
        member_id, card_id, last_4_digits, card_type, card_brand,
        creation_date, deleted_date, expiration_date,
        balance_or_credit_limit, credit_used, credit_used_percentage,
        status, delinquency_bracket, activation_date, is_activated,
        fraud_incident, last_activity_date, card_source,
        member_phone, member_email
    FROM credit_card_accounts
) uc
LEFT JOIN member_card_types mct ON uc.member_id = mct.member_id

ORDER BY 
    uc.member_id, 
    uc.card_source,
    uc.card_type, 
    uc.creation_date desc