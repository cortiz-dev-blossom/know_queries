SELECT 
    -- Member Identifiers
    m.member_number as member_id,
    
    -- Name fields
CASE 
    WHEN e.name_first IS NULL OR e.name_first = '[NULL]' 
    THEN NULL
    ELSE CONCAT(UPPER(LEFT(e.name_first, 1)), LOWER(SUBSTRING(e.name_first, 2)))
END AS first_name,

CASE 
    WHEN e.name_middle IS NULL OR e.name_middle = '[NULL]' 
    THEN NULL
    ELSE CONCAT(UPPER(LEFT(e.name_middle, 1)), LOWER(SUBSTRING(e.name_middle, 2)))
END AS middle_name,

CONCAT(UPPER(LEFT(e.name_last, 1)), LOWER(SUBSTRING(e.name_last, 2))) AS last_name,

e.preferred_name AS preferred_name,
pn.phone_number AS member_phone,
e.email1 AS member_email,

    -- Credit Score Information
    e.credit_score AS credit_score,
    e.credit_score_code AS credit_score_code,
    e.credit_score_date AS credit_score_date,
    CASE 
        WHEN e.credit_score IS NULL THEN 'No Score'
        WHEN e.credit_score = 0 THEN 'No Score'
        WHEN e.credit_score BETWEEN 1 AND 579 THEN 'Very Poor'
        WHEN e.credit_score BETWEEN 580 AND 669 THEN 'Fair'
        WHEN e.credit_score BETWEEN 670 AND 739 THEN 'Good'
        WHEN e.credit_score BETWEEN 740 AND 799 THEN 'Very Good'
        WHEN e.credit_score >= 800 THEN 'Exceptional'
        ELSE 'Unknown'
    END AS credit_score_category,

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
    YEAR(CURDATE()) - YEAR(e.dob) AS age,
    
    -- Member Status Fields (for dashboard filtering)
    CASE
        WHEN m.inactive_flag = 'I' THEN 'Inactive'
        ELSE 'Active'
    END member_status,
    
    -- NEW: Filter columns for dashboard (same as product_overview.sql)
    CASE WHEN m.member_number > 0 THEN 'Valid' ELSE 'Invalid' END AS member_number_is_valid,
    CASE WHEN m.inactive_flag = 'I' THEN 'Inactive Flag' ELSE 'Active Flag' END AS member_inactive_flag_status,
    -- UPDATED: Match user query logic - exclude NULL values
    CASE 
        WHEN all_accounts_closed = 1 THEN 'All Closed'
        WHEN all_accounts_closed = 0 THEN 'Has Open Accounts'
        ELSE 'Unknown/NULL'
    END AS member_accounts_status,
    m.inactive_flag AS member_inactive_flag_code,
    m.all_accounts_closed AS member_all_accounts_closed_flag,
    
    CASE 
        WHEN m.member_type = 'P' THEN 'Personal'
        WHEN m.member_type = 'B' THEN 'Business'
        WHEN m.member_type = 'C' THEN 'Corporate Member'
        ELSE 'Unknown'
    END as member_type,
    
    -- Data for Time Series Analysis
    DATE(m.join_date) as join_date,
    YEAR(m.join_date) as join_year,
    QUARTER(m.join_date) as join_quarter,
    MONTH(m.join_date) as join_month,
    DATEDIFF(CURDATE(), m.join_date) as member_tenure_days,
    CASE 
        WHEN DATEDIFF(CURDATE(), m.join_date) < 183 THEN '1. Recent (0-6 months)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 365 THEN '2. New (6-12 months)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 1095 THEN '3. Established (1-3 years)'
        WHEN DATEDIFF(CURDATE(), m.join_date) < 1825 THEN '4. Mature (3-5 years)'
        ELSE '5. Veteran (5+ years)'
    END as member_tenure_category,
        
    -- Demographics from Entity table
    CASE
        WHEN e.gender = 'F' THEN 'Female'
        WHEN e.gender = 'M' THEN 'Male'
        WHEN e.gender = 'N' THEN 'Non-Binary'
        WHEN e.gender = 'O' THEN 'Opt Out'
        ELSE 'Unknown'
    END as gender,
    CASE 
	    WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 0 AND 17 THEN '0-17'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 18 AND 25 THEN '18-25'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 26 AND 35 THEN '26-35'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 36 AND 45 THEN '36-45'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 46 AND 55 THEN '46-55'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 56 AND 65 THEN '56-65'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 66 AND 75 THEN '66-75'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) BETWEEN 76 AND 85 THEN '76-85'
        WHEN YEAR(CURDATE()) - YEAR(e.dob) > 85 THEN '85+'
        ELSE 'Unknown'
    END as age_group,
    YEAR(CURDATE()) - YEAR(e.dob) as calculated_age,
    


-- Geographic Data - Standardized with UPPER() and TRIM(): If foreign_address = 1, use physical; otherwise use regular address
    CASE 
        WHEN e.foreign_address = 1 THEN UPPER(TRIM(e.physical_address1))
        ELSE UPPER(TRIM(e.address1))
    END as address1,

    CASE 
        WHEN e.foreign_address = 1 THEN UPPER(TRIM(e.physical_address2))
        ELSE UPPER(TRIM(e.address2))
    END as address2,

    CASE 
        WHEN e.foreign_address = 1 THEN COALESCE(UPPER(TRIM(e.physical_city)), 'Unknown')
        ELSE COALESCE(UPPER(TRIM(e.city)), 'Unknown')
    END as city,

    CASE 
        WHEN e.foreign_address = 1 THEN COALESCE(UPPER(TRIM(e.physical_state)), 'Unknown')
        ELSE COALESCE(UPPER(TRIM(e.state)), 'Unknown')
    END as state,

    CASE 
        WHEN e.foreign_address = 1 THEN COALESCE(UPPER(TRIM(e.physical_zip)), 'Unknown')
        ELSE COALESCE(UPPER(TRIM(e.zip)), 'Unknown')
    END as zip_code,

    CASE 
        WHEN e.foreign_address = 1 THEN COALESCE(UPPER(TRIM(e.physical_country)), 'Unknown')
        ELSE COALESCE(UPPER(TRIM(e.country)), 'Unknown')
    END as country,

    -- Combined city_state field
    CASE 
        WHEN e.foreign_address = 1 THEN CONCAT(COALESCE(UPPER(TRIM(e.physical_city)), 'Unknown'), ', ', COALESCE(UPPER(TRIM(e.physical_state)), 'Unknown'))
        ELSE CONCAT(COALESCE(UPPER(TRIM(e.city)), 'Unknown'), ', ', COALESCE(UPPER(TRIM(e.state)), 'Unknown'))
    END as city_state,

    -- Address type used
    CASE 
        WHEN e.foreign_address = 1 THEN 'Physical'
        ELSE 'Mailing'
    END as address_type_used,
    
    -- Branch and Organizational Data
    m.branch_number as branch,
    COALESCE(eg.description, 'Unknown') as eligibility_group,
    
    -- Engagement Metrics
    CASE 
        WHEN m.home_bank_date IS NOT NULL THEN 'Active'
        ELSE 'Inactive'
    END as online_banking_status,
    
    CASE 
        WHEN m.last_nondiv_activity >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN 'Active'
        WHEN m.last_nondiv_activity IS NOT NULL THEN 'Inactive'
        ELSE 'Unknown'
    END as activity_30_days,
    
    CASE 
        WHEN m.last_nondiv_activity >= DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 'Active'
        WHEN m.last_nondiv_activity IS NOT NULL THEN 'Inactive'
        ELSE 'Unknown'
    END as activity_90_days,
    
    -- OPTIMIZED: Consolidated Account Counts from single subquery
    COALESCE(account_summary.total_account_count, 0) as total_account_count,
    
    -- Account Summary by Product Type (from consolidated subquery)
    COALESCE(account_summary.share_count, 0) as savings_accounts_count,
    COALESCE(account_summary.draft_count, 0) as checking_accounts_count,
    COALESCE(account_summary.loan_count, 0) as loan_accounts_count,
    COALESCE(account_summary.cert_count, 0) as certificate_accounts_count,
    
    -- Product Type Indicators (binary flags for each product type)
    CASE WHEN COALESCE(account_summary.share_count, 0) > 0 THEN 1 ELSE 0 END as has_savings,
    CASE WHEN COALESCE(account_summary.draft_count, 0) > 0 THEN 1 ELSE 0 END as has_checking,
    CASE WHEN COALESCE(account_summary.loan_count, 0) > 0 THEN 1 ELSE 0 END as has_loans,
    CASE WHEN COALESCE(account_summary.cert_count, 0) > 0 THEN 1 ELSE 0 END as has_certificates,
    
    -- Count of distinct product types (not accounts)
    (CASE WHEN COALESCE(account_summary.share_count, 0) > 0 THEN 1 ELSE 0 END +
     CASE WHEN COALESCE(account_summary.draft_count, 0) > 0 THEN 1 ELSE 0 END +
     CASE WHEN COALESCE(account_summary.loan_count, 0) > 0 THEN 1 ELSE 0 END +
     CASE WHEN COALESCE(account_summary.cert_count, 0) > 0 THEN 1 ELSE 0 END) as distinct_product_types_count,
    
    -- Total Product Relationships (using consolidated counts)
    (COALESCE(account_summary.share_count, 0) + 
     COALESCE(account_summary.draft_count, 0) + 
     COALESCE(account_summary.loan_count, 0) + 
     COALESCE(account_summary.cert_count, 0)) as total_products_by_type,
    
    -- Product Relationship Categories based on PRODUCT TYPES, not account counts
    CASE 
        WHEN COALESCE(account_summary.total_account_count, 0) = 0 THEN 'No Products'
        WHEN (CASE WHEN COALESCE(account_summary.share_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.draft_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.loan_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.cert_count, 0) > 0 THEN 1 ELSE 0 END) = 1 THEN 'Single Product'
        WHEN (CASE WHEN COALESCE(account_summary.share_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.draft_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.loan_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.cert_count, 0) > 0 THEN 1 ELSE 0 END) = 4 THEN 'Full Relationship'
        WHEN (CASE WHEN COALESCE(account_summary.share_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.draft_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.loan_count, 0) > 0 THEN 1 ELSE 0 END +
              CASE WHEN COALESCE(account_summary.cert_count, 0) > 0 THEN 1 ELSE 0 END) BETWEEN 2 AND 3 THEN 'Multi Product'
        ELSE 'Unknown'
    END as product_relationship_category,
    
    -- Digital Engagement Score (using consolidated account count)
    (CASE WHEN m.home_bank_date IS NOT NULL THEN 40 ELSE 0 END +
     CASE WHEN m.last_nondiv_activity >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) THEN 30 ELSE 0 END +
     CASE WHEN m.last_nondiv_activity >= DATE_SUB(CURDATE(), INTERVAL 90 DAY) THEN 20 ELSE 0 END +
     CASE WHEN COALESCE(account_summary.total_account_count, 0) > 1 THEN 10 ELSE 0 END) as engagement_score,
    
    -- Additional useful fields
    m.last_nondiv_activity as last_activity_date,
    m.home_bank_date as last_online_banking_date,
    CASE WHEN m.all_accounts_closed = 1 THEN 'Yes' ELSE 'No' END as all_accounts_closed_legacy,
    
    -- Attrition Analysis Fields
    attrition_data.latest_account_closure_date as attrition_date,
    CASE 
        WHEN m.all_accounts_closed = 1 AND attrition_data.latest_account_closure_date IS NOT NULL 
        THEN DATEDIFF(attrition_data.latest_account_closure_date, m.join_date)
        ELSE NULL
    END as member_lifespan_days,
    
    CASE 
        WHEN m.all_accounts_closed = 1 AND attrition_data.latest_account_closure_date IS NOT NULL 
        THEN 
            CASE 
                WHEN DATEDIFF(attrition_data.latest_account_closure_date, m.join_date) < 90 THEN 'Early (0-3 months)'
                WHEN DATEDIFF(attrition_data.latest_account_closure_date, m.join_date) < 365 THEN 'Short (3-12 months)'
                WHEN DATEDIFF(attrition_data.latest_account_closure_date, m.join_date) < 1095 THEN 'Medium (1-3 years)'
                WHEN DATEDIFF(attrition_data.latest_account_closure_date, m.join_date) < 1825 THEN 'Long (3-5 years)'
                ELSE 'Very Long (5+ years)'
            END
        ELSE NULL
    END as attrition_category,
    
    -- Current Date for Refresh Tracking
    CURDATE() as data_extract_date

FROM   member m
LEFT JOIN entity e ON m.member_entity_id = e.entity_id
LEFT JOIN eligibility_group eg ON m.eligibility_group_id = eg.eligibility_group_id
LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1

-- OPTIMIZED: Single consolidated account summary subquery (active accounts only)
LEFT JOIN (
    SELECT 
        member_number,
        COUNT(DISTINCT account_id) as total_account_count,
        COUNT(DISTINCT CASE WHEN discriminator = 'S' THEN account_id END) as share_count,
        COUNT(DISTINCT CASE WHEN discriminator = 'D' THEN account_id END) as draft_count,
        COUNT(DISTINCT CASE WHEN discriminator = 'L' THEN account_id END) as loan_count,
        COUNT(DISTINCT CASE WHEN discriminator = 'C' THEN account_id END) as cert_count
    FROM account 
    WHERE date_closed IS NULL
    GROUP BY member_number
) account_summary ON m.member_number = account_summary.member_number

-- Attrition date calculation - latest account closure for churned members
LEFT JOIN (
    SELECT 
        a.member_number,
        MAX(a.date_closed) as latest_account_closure_date
    FROM account a
    INNER JOIN member m ON a.member_number = m.member_number
    WHERE a.date_closed IS NOT NULL 
      AND m.all_accounts_closed = 1
    GROUP BY a.member_number
) attrition_data ON m.member_number = attrition_data.member_number
ORDER BY m.member_number