-- ========================================================================
-- MWCU LOAN AGE ANALYSIS - MOROSIDAD CON EDAD DE PRÉSTAMOS
-- Business Purpose: Análisis de morosidad comparativa con categorización de edad
-- Created: 3 de octubre de 2025
-- Updated: 27 de noviembre de 2025
-- Database: MINNEQUA WORKS CREDIT UNION (mwcu schema)
-- Período: DINÁMICO - Último mes cerrado vs Mes anterior
-- ========================================================================

WITH date_params AS (
    -- Genera las fechas dinámicamente: último día del mes pasado y mes anterior
    SELECT 
        LAST_DAY(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)) AS current_month_end,
        LAST_DAY(DATE_SUB(CURDATE(), INTERVAL 2 MONTH)) AS previous_month_end
),
base AS (
    SELECT
        l.record_date,
        DATE_FORMAT(l.record_date, '%Y-%m') AS record_ym,
        a.member_number,
        a.account_number,
        a.account_id,
        al.credit_score,
        al.credit_score_code,
        a.date_opened,
        l.balance,
        l.next_payment_date,
        
        -- CÁLCULO DE EDAD DEL PRÉSTAMO EN MESES
        CASE WHEN a.date_opened IS NOT NULL THEN 
          TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) 
        ELSE NULL END AS loan_age_months,
        
        -- CATEGORIZACIÓN DE EDAD DEL PRÉSTAMO
        CASE 
          WHEN a.date_opened IS NULL THEN 'No Account Data'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) <= 6 THEN '0-6 months'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) BETWEEN 7 AND 12 THEN '7-12 months'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) BETWEEN 13 AND 24 THEN '13-24 months'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) BETWEEN 25 AND 36 THEN '25-36 months'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) BETWEEN 37 AND 60 THEN '37-60 months'
          WHEN TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) > 60 THEN 'Over 60 months'
          ELSE 'Unknown'
        END AS loan_age_category,
        
        -- PLAZO ORIGINAL DEL PRÉSTAMO
        al.number_of_payments AS original_loan_term_months,
        al.payments_per_year,
        al.maturity_date,
        
        -- CATEGORIZACIÓN DEL PLAZO ORIGINAL
        CASE 
          WHEN al.number_of_payments IS NULL OR al.number_of_payments = 0 THEN 'No Term Data'
          WHEN al.number_of_payments >= 999 THEN 'Line of Credit'
          WHEN al.number_of_payments <= 12 THEN '1 year or less'
          WHEN al.number_of_payments BETWEEN 13 AND 24 THEN '13-24 months'
          WHEN al.number_of_payments BETWEEN 25 AND 36 THEN '25-36 months'
          WHEN al.number_of_payments BETWEEN 37 AND 48 THEN '37-48 months'
          WHEN al.number_of_payments BETWEEN 49 AND 60 THEN '49-60 months'
          WHEN al.number_of_payments BETWEEN 61 AND 72 THEN '61-72 months'
          WHEN al.number_of_payments BETWEEN 73 AND 84 THEN '73-84 months'
          WHEN al.number_of_payments > 84 THEN 'Over 84 months'
          ELSE 'Other Term'
        END AS loan_term_category,
        
        -- INFORMACIÓN FINANCIERA DEL PRÉSTAMO
        al.opening_balance AS original_loan_amount,
        al.highest_balance_attained,
        al.interest_rate,
        al.payment_periodic AS scheduled_payment,
        al.amount_delq AS delinquent_amount,
        al.last_payment_date,
        al.interest_accumulated,
        al.principal_and_interest,
        
        -- ===============================
        -- INDICADOR DE PRIMER PAGO VENCIDO Y NO REALIZADO
        -- ===============================
        CASE 
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
          THEN 1
          ELSE 0
        END AS missed_first_payment_flag,
        
        CASE 
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
          THEN 'Missed First Payment (Overdue)'
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) = 0 
          THEN 'Due Today (Not Paid Yet)'
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) < 0 
          THEN 'No Payment Yet (Not Due)'
          WHEN al.last_payment_date IS NOT NULL THEN 'Has Made Payment(s)'
          ELSE 'Unknown'
        END AS first_payment_status,
        
        -- Días vencidos del primer pago sin realizar
        CASE 
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
          THEN DATEDIFF(l.record_date, l.next_payment_date)
          ELSE NULL
        END AS days_overdue_first_payment,
        
        -- Categorización por días vencidos del primer pago
        CASE 
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
          THEN
            CASE 
              WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 1 AND 30 THEN 'Missed 1-30 days'
              WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 31 AND 60 THEN 'Missed 31-60 days'
              WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 61 AND 90 THEN 'Missed 61-90 days'
              WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 91 AND 120 THEN 'Missed 91-120 days'
              WHEN DATEDIFF(l.record_date, l.next_payment_date) > 120 THEN 'Missed Over 120 days (Critical)'
              ELSE 'Unknown'
            END
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) = 0 
          THEN 'Due Today'
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) < 0 
          THEN 'Not Due Yet'
          WHEN al.last_payment_date IS NOT NULL THEN 'Has Made Payments'
          ELSE 'No Date Data'
        END AS first_payment_overdue_category,
        
        -- RATIOS DE RIESGO CALCULADOS
        CASE WHEN al.opening_balance > 0 THEN 
          (l.balance / al.opening_balance) * 100 
        ELSE NULL END AS loan_utilization_pct,
        
        CASE WHEN al.opening_balance > 0 THEN 
          ((al.opening_balance - l.balance) / al.opening_balance) * 100 
        ELSE NULL END AS loan_paydown_pct,
        
        CASE WHEN l.balance > 0 AND al.payment_periodic > 0 THEN 
          (al.payment_periodic / l.balance) * 100 
        ELSE NULL END AS payment_to_balance_ratio,
        
        CASE WHEN al.number_of_payments > 0 THEN 
          (TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) / al.number_of_payments) * 100 
        ELSE NULL END AS loan_progress_pct,
        
        -- CATEGORIZACIÓN POR MONTO ORIGINAL
        CASE 
          WHEN al.opening_balance <= 5000 THEN 'Micro ($0-$5K)'
          WHEN al.opening_balance BETWEEN 5001 AND 15000 THEN 'Small ($5K-$15K)'
          WHEN al.opening_balance BETWEEN 15001 AND 50000 THEN 'Medium ($15K-$50K)'
          WHEN al.opening_balance BETWEEN 50001 AND 100000 THEN 'Large ($50K-$100K)'
          WHEN al.opening_balance > 100000 THEN 'Jumbo ($100K+)'
          ELSE 'No Amount Data'
        END AS loan_amount_category,
        
        -- CATEGORIZACIÓN POR TASA DE INTERÉS
        CASE 
          WHEN al.interest_rate <= 5.00 THEN 'Prime (≤5%)'
          WHEN al.interest_rate BETWEEN 5.01 AND 8.00 THEN 'Near-Prime (5-8%)'
          WHEN al.interest_rate BETWEEN 8.01 AND 12.00 THEN 'Standard (8-12%)'
          WHEN al.interest_rate BETWEEN 12.01 AND 18.00 THEN 'Subprime (12-18%)'
          WHEN al.interest_rate > 18.00 THEN 'High-Risk (>18%)'
          ELSE 'No Rate Data'
        END AS interest_rate_category,
        
        -- RATIOS CATEGORIZADOS PARA SEGMENTACIÓN
        
        -- Utilización del préstamo (categórico)
        CASE 
          WHEN al.opening_balance = 0 THEN 'No Data'
          WHEN (l.balance / al.opening_balance) * 100 <= 25 THEN 'Low Utilization (≤25%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 25.01 AND 50 THEN 'Moderate Utilization (25-50%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 50.01 AND 75 THEN 'High Utilization (50-75%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 75.01 AND 90 THEN 'Very High Utilization (75-90%)'
          WHEN (l.balance / al.opening_balance) * 100 > 90 THEN 'Critical Utilization (>90%)'
          ELSE 'Unknown'
        END AS loan_utilization_category,
        
        -- Progreso de pago (categórico)
        CASE 
          WHEN al.opening_balance = 0 THEN 'No Data'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 <= 10 THEN 'Minimal Paydown (≤10%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 10.01 AND 25 THEN 'Low Paydown (10-25%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 25.01 AND 50 THEN 'Moderate Paydown (25-50%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 50.01 AND 75 THEN 'Good Paydown (50-75%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 > 75 THEN 'Excellent Paydown (>75%)'
          ELSE 'Unknown'
        END AS loan_paydown_category,
        
        -- Capacidad de pago (categórico)
        CASE 
          WHEN l.balance = 0 OR al.payment_periodic = 0 THEN 'No Data'
          WHEN (al.payment_periodic / l.balance) * 100 < 1 THEN 'Very Low Capacity (<1%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 1 AND 2 THEN 'Low Capacity (1-2%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 2.01 AND 4 THEN 'Moderate Capacity (2-4%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 4.01 AND 8 THEN 'Good Capacity (4-8%)'
          WHEN (al.payment_periodic / l.balance) * 100 > 8 THEN 'Excellent Capacity (>8%)'
          ELSE 'Unknown'
        END AS payment_capacity_category,
        
        -- Progreso en plazo del préstamo (categórico)
        CASE 
          WHEN al.number_of_payments = 0 THEN 'No Term Data'
          WHEN (TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) / al.number_of_payments) * 100 <= 25 THEN 'Early Stage (≤25%)'
          WHEN (TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) / al.number_of_payments) * 100 BETWEEN 25.01 AND 50 THEN 'Mid-Early Stage (25-50%)'
          WHEN (TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) / al.number_of_payments) * 100 BETWEEN 50.01 AND 75 THEN 'Mid-Late Stage (50-75%)'
          WHEN (TIMESTAMPDIFF(MONTH, a.date_opened, l.record_date) / al.number_of_payments) * 100 > 75 THEN 'Final Stage (>75%)'
          ELSE 'Unknown'
        END AS loan_lifecycle_stage,
        
        -- CLASIFICACIÓN DE RIESGO COMBINADA
        CASE 
          WHEN al.opening_balance = 0 OR l.balance = 0 OR al.payment_periodic = 0 THEN 'Insufficient Data'
          WHEN (l.balance / al.opening_balance) * 100 > 90 
          AND (al.payment_periodic / l.balance) * 100 < 2 THEN 'High Risk'
          WHEN (l.balance / al.opening_balance) * 100 > 75 
          AND (al.payment_periodic / l.balance) * 100 < 3 THEN 'Elevated Risk'
          WHEN (l.balance / al.opening_balance) * 100 < 50 
          AND (al.payment_periodic / l.balance) * 100 > 4 THEN 'Low Risk'
          ELSE 'Moderate Risk'
        END AS combined_risk_category,
        
        -- INFORMACIÓN DE ORIGINACIÓN
        al.loan_purpose_code_id,
        al.loan_officer_userid,
        m.branch_number,
        
        -- CATEGORIZACIÓN DESCRIPTIVA DE SUCURSAL
        CASE 
          WHEN m.branch_number = 0 THEN 'Branch 0 - Digital/Online'
          WHEN m.branch_number = 1 THEN 'Branch 1 - Main Branch'
          WHEN m.branch_number = 2 THEN 'Branch 2 - Secondary'
          WHEN m.branch_number = 3 THEN 'Branch 3 - Regional'
          WHEN m.branch_number = 4 THEN 'Branch 4 - Metropolitan'
          WHEN m.branch_number = 5 THEN 'Branch 5 - Suburban'
          WHEN m.branch_number = 6 THEN 'Branch 6 - Special Services'
          WHEN m.branch_number >= 7 THEN 'Branch 7+ - Other Locations'
          ELSE 'Unknown Branch'
        END AS branch_description,
        
        -- CATEGORIZACIÓN POR TAMAÑO DE SUCURSAL
        CASE 
          WHEN m.branch_number = 1 THEN 'Large Branch (20K+ members)'
          WHEN m.branch_number IN (0, 4, 5) THEN 'Medium Branch (5K-15K members)'
          WHEN m.branch_number IN (2, 3) THEN 'Small Branch (1K-5K members)'
          WHEN m.branch_number = 6 THEN 'Specialty Branch (<100 members)'
          ELSE 'Other Size'
        END AS branch_size_category,
        
        -- ===============================
        -- INFORMACIÓN DEMOGRÁFICA DEL MIEMBRO
        -- ===============================
        
        -- Edad del miembro
        CASE 
          WHEN e.dob IS NULL THEN NULL
          ELSE TIMESTAMPDIFF(YEAR, e.dob, l.record_date)
        END AS member_age_years,
        
        -- Categorización por edad
        CASE 
          WHEN e.dob IS NULL THEN 'Age Unknown'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) < 25 THEN 'Under 25'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) BETWEEN 25 AND 34 THEN '25-34 years'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) BETWEEN 35 AND 44 THEN '35-44 years'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) BETWEEN 45 AND 54 THEN '45-54 years'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) BETWEEN 55 AND 64 THEN '55-64 years'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) BETWEEN 65 AND 74 THEN '65-74 years'
          WHEN TIMESTAMPDIFF(YEAR, e.dob, l.record_date) >= 75 THEN '75+ years'
          ELSE 'Age Unknown'
        END AS member_age_category,
        
        -- Género
        CASE 
          WHEN e.gender = 'M' THEN 'Male'
          WHEN e.gender = 'F' THEN 'Female'
          WHEN e.gender = 'O' THEN 'Other'
          WHEN e.gender = '' OR e.gender IS NULL THEN 'Unknown'
          ELSE 'Other'
        END AS member_gender,
        
        -- Información geográfica
        e.city AS member_city,
        e.state AS member_state,
        SUBSTRING(e.zip, 1, 5) AS member_zip5,
        
        -- Categorización por estado (Colorado vs Fuera de estado)
        CASE 
          WHEN e.state = 'CO' THEN 'Colorado Resident'
          WHEN e.state IN ('TX', 'AZ', 'CA', 'NM', 'FL', 'KS', 'WA', 'MO', 'OK') THEN 'Major Out-of-State'
          WHEN e.state IS NOT NULL AND e.state != '' AND e.state != 'CO' THEN 'Other Out-of-State'
          ELSE 'Unknown State'
        END AS member_state_category,
        
        -- Información profesional
        e.occupation AS member_occupation,
        e.naics_occupation_code,
        
        -- Categorización por ocupación (análisis general)
        CASE 
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%RETIRED%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%RETIREMENT%' THEN 'Retired'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%STUDENT%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%SCHOOL%' THEN 'Student'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%TEACHER%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%EDUCATION%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%PROFESSOR%' THEN 'Education'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%NURSE%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%DOCTOR%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%MEDICAL%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%HEALTHCARE%' THEN 'Healthcare'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%ENGINEER%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%TECHNICIAN%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%IT %' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%COMPUTER%' THEN 'Engineering/Tech'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%MANAGER%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%DIRECTOR%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%EXECUTIVE%' THEN 'Management'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%SALES%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%MARKETING%' THEN 'Sales/Marketing'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%GOVERNMENT%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%FEDERAL%' OR
              UPPER(COALESCE(e.occupation, '')) LIKE '%STATE %' THEN 'Government'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%UNEMPLOYED%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%NOT EMPLOYED%' THEN 'Unemployed'
          WHEN UPPER(COALESCE(e.occupation, '')) LIKE '%HOMEMAKER%' OR 
              UPPER(COALESCE(e.occupation, '')) LIKE '%HOUSEWIFE%' THEN 'Homemaker'
          WHEN COALESCE(e.occupation, '') = '' THEN 'Unknown Occupation'
          ELSE 'Other Occupation'
        END AS member_occupation_category,
        
        -- Antigüedad como miembro
        CASE 
          WHEN m.join_date IS NULL THEN NULL
          ELSE TIMESTAMPDIFF(YEAR, m.join_date, l.record_date)
        END AS member_tenure_years,
        
        -- Categorización por antigüedad
        CASE 
          WHEN m.join_date IS NULL THEN 'Unknown Tenure'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) < 1 THEN 'New Member (<1 year)'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 1 AND 2 THEN 'Recent Member (1-2 years)'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 3 AND 5 THEN 'Established Member (3-5 years)'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 6 AND 10 THEN 'Long-term Member (6-10 years)'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 11 AND 20 THEN 'Veteran Member (11-20 years)'
          WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) > 20 THEN 'Legacy Member (20+ years)'
          ELSE 'Unknown Tenure'
        END AS member_tenure_category,
        
        -- Información de riesgo del miembro
        m.collection_queue_id,
        m.delinquency_status_code_id,
        m.date_first_delinquent,
        
        -- Flag de miembro con historial de morosidad
        CASE 
          WHEN m.date_first_delinquent IS NOT NULL THEN 'Has Delinquency History'
          ELSE 'No Known Delinquency History'
        END AS member_delinquency_history,
        
        -- Número de cuentas del miembro
        m.number_of_accounts AS member_total_accounts,
        
        -- Categorización por número de productos
        CASE 
          WHEN m.number_of_accounts <= 1 THEN 'Single Product (1 account)'
          WHEN m.number_of_accounts BETWEEN 2 AND 3 THEN 'Multi-Product (2-3 accounts)'
          WHEN m.number_of_accounts BETWEEN 4 AND 6 THEN 'High Engagement (4-6 accounts)'
          WHEN m.number_of_accounts > 6 THEN 'Very High Engagement (7+ accounts)'
          ELSE 'Unknown Engagement'
        END AS member_engagement_level,
        
        IF(DATEDIFF(l.record_date, l.next_payment_date) < 0, 0,
          DATEDIFF(l.record_date, l.next_payment_date)) AS days_delinquent,
        CASE 
          WHEN al.last_payment_date IS NULL 
            AND l.next_payment_date IS NOT NULL
            AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
          THEN 'First Payment Delinquency'
          WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 1 AND 30  THEN '1-30 days'
          WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 31 AND 60 THEN '31-60 days'
          WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 61 AND 90 THEN '61-90 days'
          WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 91 AND 120 THEN '91-120 days'
          WHEN DATEDIFF(l.record_date, l.next_payment_date) > 120          THEN 'Over 120 days'
          ELSE '0 days'
        END AS Delinquency_Bracket,
        t.credit_card,
        UPPER(COALESCE(t.description, '')) AS desc_u,
        t.cb_loan_type,
        -- CATEGORIZACIÓN BASADA EN CREDIT BUREAU LOAN TYPE
        CASE 
          WHEN t.cb_loan_type = '00' THEN 'Auto Loans'
          WHEN t.cb_loan_type = '01' THEN 'Unsecured/Personal Loans'
          WHEN t.cb_loan_type = '02' THEN 'Share/CD Secured Loans'
          WHEN t.cb_loan_type = '03' THEN 'Signature Secured Loans'
          WHEN t.cb_loan_type = '11' THEN 'Recreational Vehicle Loans'
          WHEN t.cb_loan_type = '15' THEN 'Overdraft Protection'
          WHEN t.cb_loan_type = '18' THEN 'Credit Card'
          WHEN t.cb_loan_type = '26' THEN 'Real Estate/Mortgage Loans'
          WHEN t.cb_loan_type = '89' THEN 'Home Equity Loans'
          ELSE 'Unclassified'
        END AS loan_main_category,
        
        -- Información de contacto del miembro
        pn.phone_number AS member_phone,
        e.email1 AS member_email
    FROM eom_loan l
    CROSS JOIN date_params dp
    JOIN account a ON a.account_id = l.account_id
    JOIN account_loan al ON a.account_id = al.account_id
    JOIN account_types t ON t.account_type = l.account_type
    JOIN member m ON a.member_number = m.member_number
    JOIN entity e ON m.member_entity_id = e.entity_id
    LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
    WHERE l.record_date IN (dp.previous_month_end, dp.current_month_end)
      AND l.date_closed IS NULL
      AND l.balance > 0
      AND COALESCE(a.current_balance, l.balance) > 0
      AND COALESCE(t.credit_card,'N') NOT IN ('Y','X','1')
  ),
  -- ========================================================================
  -- MÉTRICAS DE PORTFOLIO Y CONCENTRACIÓN POR MIEMBRO
  -- ========================================================================
  member_portfolio AS (
    SELECT 
        a.member_number,
        COUNT(DISTINCT el.account_id) AS member_total_loans,
        SUM(el.balance) AS member_total_loan_balance,
        SUM(CASE WHEN DATEDIFF(el.record_date, el.next_payment_date) > 0 
            THEN el.balance ELSE 0 END) AS member_total_delinquent_balance,
        MAX(DATEDIFF(el.record_date, el.next_payment_date)) AS member_worst_delinquency_days,
        SUM(CASE WHEN DATEDIFF(el.record_date, el.next_payment_date) > 0 
            THEN 1 ELSE 0 END) AS member_delinquent_loan_count,
        -- Categorización de exposición
        CASE 
            WHEN SUM(el.balance) <= 10000 THEN 'Low Exposure (≤$10K)'
            WHEN SUM(el.balance) BETWEEN 10001 AND 50000 THEN 'Medium Exposure ($10K-$50K)'
            WHEN SUM(el.balance) BETWEEN 50001 AND 100000 THEN 'High Exposure ($50K-$100K)'
            WHEN SUM(el.balance) > 100000 THEN 'Very High Exposure (>$100K)'
            ELSE 'Unknown'
        END AS member_exposure_category,
        -- Flag de cross-delinquency (múltiples préstamos morosos)
        CASE 
            WHEN COUNT(DISTINCT el.account_id) > 1 
                AND SUM(CASE WHEN DATEDIFF(el.record_date, el.next_payment_date) > 0 THEN 1 ELSE 0 END) > 1 
                THEN 1 
            ELSE 0 
        END AS has_multiple_delinquent_loans
    FROM eom_loan el
    CROSS JOIN date_params dp
    JOIN account a ON el.account_id = a.account_id
    WHERE el.record_date = dp.current_month_end
      AND el.date_closed IS NULL
      AND el.balance > 0
    GROUP BY a.member_number
  ),
  -- ========================================================================
  -- ACCIONES DE COBRANZA - ÚLTIMOS 90 DÍAS
  -- ========================================================================
  collection_activity AS (
    SELECT 
        ch.account_id,
        COUNT(*) AS collection_contacts_90d,
        COUNT(DISTINCT DATE(ch.created_timestamp)) AS collection_contact_days_90d,
        SUM(CASE WHEN ch.promise_to_pay = 1 THEN 1 ELSE 0 END) AS promises_made_90d,
        SUM(ch.promise_to_pay_amt) AS total_promise_amount_90d,
        SUM(ch.actual_amount_paid) AS total_collected_90d,
        MAX(ch.created_timestamp) AS last_collection_contact_date,
        DATEDIFF(CURDATE(), MAX(ch.created_timestamp)) AS days_since_last_contact,
        -- Última acción de cobranza
        SUBSTRING_INDEX(GROUP_CONCAT(
            COALESCE(cca.description, 'UNSPECIFIED') 
            ORDER BY ch.created_timestamp DESC 
            SEPARATOR '|||'
        ), '|||', 1) AS last_collection_action,
        -- Usuario que realizó último contacto
        SUBSTRING_INDEX(GROUP_CONCAT(
            ch.created_by_userid 
            ORDER BY ch.created_timestamp DESC 
            SEPARATOR '|||'
        ), '|||', 1) AS last_collection_user,
        -- Promesas pendientes (últimos 30 días hacia adelante)
        SUM(CASE 
            WHEN ch.promise_to_pay = 1 
            AND ch.promise_to_pay_date >= CURDATE()
            AND ch.promise_to_pay_date <= DATE_ADD(CURDATE(), INTERVAL 30 DAY)
            THEN ch.promise_to_pay_amt 
            ELSE 0 
        END) AS pending_promises_next_30d,
        -- Efectividad de cobranza
        CASE 
            WHEN SUM(ch.promise_to_pay_amt) > 0 
            THEN ROUND((SUM(ch.actual_amount_paid) / SUM(ch.promise_to_pay_amt)) * 100, 2)
            ELSE NULL 
        END AS collection_effectiveness_pct
    FROM collection_history ch
    LEFT JOIN collection_custom_action cca ON ch.collection_custom_action_id = cca.collection_custom_action_id
    WHERE ch.created_timestamp >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    GROUP BY ch.account_id
  ),
  -- ========================================================================
  -- INFORMACIÓN DE COLLECTION QUEUE ACTUAL
  -- ========================================================================
  current_collection_queue AS (
    SELECT 
        ajcq.account_id,
        cq.description AS collection_queue_name,
        cq.days_delinquent_beg AS queue_min_days,
        cq.days_delinquent_end AS queue_max_days,
        ajcq.manually_added AS manually_added_to_queue,
        ajcq.keep_in_queue AS keep_in_current_queue,
        ajcq.created_timestamp AS date_added_to_queue,
        DATEDIFF(CURDATE(), ajcq.created_timestamp) AS days_in_current_queue
    FROM account_join_collection_queue ajcq
    JOIN collection_queue cq ON ajcq.collection_queue_id = cq.collection_queue_id
  ),
  -- ========================================================================
  -- MÉTRICAS DE RECUPERACIÓN Y CHARGE-OFF
  -- Basado en account.charge_off_date (fuente primaria)
  -- ========================================================================
  recovery_metrics AS (
    SELECT 
        a.account_id,
        1 AS is_charged_off,
        a.charge_off_date,
        DATEDIFF(CURDATE(), a.charge_off_date) AS days_since_chargeoff,
        co.original_principal AS chargeoff_original_principal,
        co.principal AS chargeoff_current_principal,
        co.recovered_principal,
        co.recovered_interest,
        co.recovered_fees,
        (co.recovered_principal + co.recovered_interest + co.recovered_fees) AS total_recovered,
        CASE 
            WHEN co.original_principal > 0 
            THEN ROUND((co.recovered_principal / co.original_principal) * 100, 2)
            ELSE 0 
        END AS recovery_rate_pct,
        co.status AS chargeoff_status,
        co.bankruptcy AS bankruptcy_status,
        co.collection_agency_id AS external_agency_id,
        CASE 
            WHEN co.collection_agency_id IS NOT NULL THEN 'Placed with Agency'
            WHEN co.bankruptcy IS NOT NULL AND co.bankruptcy != '' THEN 'Bankruptcy'
            WHEN co.status = 'C' THEN 'Closed'
            WHEN co.status = 'A' THEN 'Active'
            ELSE 'Other'
        END AS recovery_status,
        co.last_payment_date AS chargeoff_last_payment_date
    FROM account a
    LEFT JOIN charge_off co ON a.account_id = co.account_id
    WHERE a.charge_off_date IS NOT NULL
  ),
  -- ========================================================================
  -- LOAN DEFERMENT STATUS
  -- ========================================================================
  loan_deferment_status AS (
    SELECT 
        ld.account_id,
        1 AS has_deferment,
        ld.start_date AS deferment_start_date,
        ld.end_deferment_date,
        ld.fully_processed AS deferment_fully_processed,
        ld.interest_accrued AS deferment_interest_accrued,
        ld.date_of_first_delinquency AS delinq_date_before_deferment,
        ld.account_status_prior_to_deferment,
        -- Estado actual del deferment
        CASE 
            WHEN ld.end_deferment_date IS NULL THEN 'Active (No End Date)'
            WHEN ld.end_deferment_date >= CURDATE() THEN 'Active Deferment'
            WHEN ld.end_deferment_date < CURDATE() 
                AND ld.end_deferment_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH) 
                THEN 'Recently Completed (<6 months)'
            WHEN ld.end_deferment_date < DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
                THEN 'Historical Deferment (>6 months ago)'
            ELSE 'Unknown'
        END AS deferment_status,
        -- Días en deferment
        CASE 
            WHEN ld.end_deferment_date IS NULL 
                THEN DATEDIFF(CURDATE(), ld.start_date)
            ELSE DATEDIFF(ld.end_deferment_date, ld.start_date)
        END AS deferment_duration_days,
        ld.created_timestamp AS deferment_created_date,
        ld.created_by_userid AS deferment_created_by
    FROM loan_deferment ld
    WHERE ld.start_date IS NOT NULL
  ),
  -- ========================================================================
  -- PAYMENT ARRANGEMENTS (SKIP/DEFERMENT)
  -- ========================================================================
  payment_arrangements AS (
    SELECT 
        lsp.account_id,
        COUNT(*) AS total_skip_payments,
        SUM(lsp.number_of_extensions) AS total_extensions,
        MAX(lsp.payment_to_skip) AS last_skip_payment_date,
        SUM(lsp.fee_amount) AS total_skip_fees,
        SUM(CASE WHEN lsp.skip_completed = 1 THEN 1 ELSE 0 END) AS completed_skips,
        -- Flag si tiene skip payment activo o futuro
        MAX(CASE 
            WHEN lsp.skip_completed = 0 AND lsp.payment_to_skip >= CURDATE() 
            THEN 1 ELSE 0 
        END) AS has_active_skip_payment,
        -- Último skip payment en últimos 3 meses
        MAX(CASE 
            WHEN lsp.payment_to_skip >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
            THEN lsp.payment_to_skip
            ELSE NULL
        END) AS recent_skip_payment_date,
        -- Flag si tuvo skip en últimos 3 meses
        MAX(CASE 
            WHEN lsp.payment_to_skip >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
            THEN 1 ELSE 0 
        END) AS has_recent_skip_payment
    FROM loan_skip_payment lsp
    WHERE lsp.payment_to_skip >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
    GROUP BY lsp.account_id
  ),
  c1 AS (   -- Consulta 1: Mes anterior
    SELECT *
    FROM base
    CROSS JOIN date_params dp
    WHERE record_date = dp.previous_month_end
  ),
  c2 AS (   -- Consulta 2: Mes actual (solo préstamos que siguen activos)
    SELECT
      l.account_id,
      IF(DATEDIFF(l.record_date, l.next_payment_date) < 0, 0,
        DATEDIFF(l.record_date, l.next_payment_date)) AS days_delinquent_m2,
      CASE 
        WHEN al.last_payment_date IS NULL 
          AND l.next_payment_date IS NOT NULL
          AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
        THEN 'First Payment Delinquency'
        WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 1 AND 30  THEN '1-30 days'
        WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 31 AND 60 THEN '31-60 days'
        WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 61 AND 90 THEN '61-90 days'
        WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 91 AND 120 THEN '91-120 days'
        WHEN DATEDIFF(l.record_date, l.next_payment_date) > 120          THEN 'Over 120 days'
        ELSE '0 days'
      END AS Delinquency_Bracket_m2
    FROM eom_loan l
    CROSS JOIN date_params dp
    JOIN account a ON a.account_id = l.account_id
    JOIN account_loan al ON a.account_id = al.account_id
    WHERE l.record_date = dp.current_month_end
      AND l.date_closed IS NULL
  ),
  -- ========================================================================
  -- MÉTRICAS AGREGADAS FIJAS - RESUMEN DE MOROSIDAD
  -- ========================================================================
  summary_m1 AS (
    SELECT 
        COUNT(DISTINCT c1.account_id) as total_loans_m1,
        SUM(c1.balance) as total_balance_m1,
        COUNT(DISTINCT CASE WHEN c1.days_delinquent > 0 THEN c1.account_id END) as delinquent_loans_m1,
        SUM(CASE WHEN c1.days_delinquent > 0 THEN c1.balance ELSE 0 END) as delinquent_balance_m1,
        ROUND((COUNT(DISTINCT CASE WHEN c1.days_delinquent > 0 THEN c1.account_id END) / COUNT(DISTINCT c1.account_id)) * 100, 2) as pct_loans_delq_m1,
        ROUND((SUM(CASE WHEN c1.days_delinquent > 0 THEN c1.balance ELSE 0 END) / SUM(c1.balance)) * 100, 2) as pct_balance_delq_m1
    FROM c1
  ),
  summary_m2 AS (
    SELECT 
        COUNT(DISTINCT c2.account_id) as total_loans_m2,
        SUM(l.balance) as total_balance_m2,
        COUNT(DISTINCT CASE WHEN c2.days_delinquent_m2 > 0 THEN c2.account_id END) as delinquent_loans_m2,
        SUM(CASE WHEN c2.days_delinquent_m2 > 0 THEN l.balance ELSE 0 END) as delinquent_balance_m2,
        ROUND((COUNT(DISTINCT CASE WHEN c2.days_delinquent_m2 > 0 THEN c2.account_id END) / COUNT(DISTINCT c2.account_id)) * 100, 2) as pct_loans_delq_m2,
        ROUND((SUM(CASE WHEN c2.days_delinquent_m2 > 0 THEN l.balance ELSE 0 END) / SUM(l.balance)) * 100, 2) as pct_balance_delq_m2
    FROM c2
    CROSS JOIN date_params dp
    JOIN eom_loan l ON c2.account_id = l.account_id AND l.record_date = dp.current_month_end
    JOIN account_types t ON t.account_type = l.account_type
    WHERE COALESCE(t.credit_card,'N') NOT IN ('Y','X','1')
  )
  SELECT
    c1.record_date,
    c1.record_ym,
    c1.member_number,
    c1.account_number,
    c1.account_id,
    c1.credit_score,
    COALESCE(c1.credit_score_code, 'No Data') AS credit_score_code,
    c1.date_opened,
    
    -- NUEVOS CAMPOS DE EDAD DEL PRÉSTAMO
    c1.loan_age_months,
    c1.loan_age_category,
    
    -- NUEVOS CAMPOS DE PLAZO ORIGINAL DEL PRÉSTAMO
    c1.original_loan_term_months,
    c1.payments_per_year,
    c1.maturity_date,
    c1.loan_term_category,
    
    -- INFORMACIÓN FINANCIERA Y RATIOS DE RIESGO
    c1.original_loan_amount,
    c1.highest_balance_attained,
    c1.interest_rate,
    c1.scheduled_payment,
    c1.delinquent_amount,
    c1.last_payment_date,
    c1.interest_accumulated,
    c1.principal_and_interest,
    
    -- INDICADORES DE PRIMER PAGO VENCIDO
    c1.missed_first_payment_flag,
    c1.first_payment_status,
    c1.days_overdue_first_payment,
    c1.first_payment_overdue_category,
    
    c1.loan_utilization_pct,
    c1.loan_paydown_pct,
    c1.payment_to_balance_ratio,
    c1.loan_progress_pct,
    c1.loan_amount_category,
    c1.interest_rate_category,
    
    -- RATIOS CATEGORIZADOS PARA SEGMENTACIÓN
    c1.loan_utilization_category,
    c1.loan_paydown_category,
    c1.payment_capacity_category,
    c1.loan_lifecycle_stage,
    c1.combined_risk_category,
    
    -- INFORMACIÓN DE ORIGINACIÓN
    c1.loan_purpose_code_id,
    c1.loan_officer_userid,
    c1.branch_number,
    c1.branch_description,
    c1.branch_size_category,
    
    -- INFORMACIÓN DEMOGRÁFICA DEL MIEMBRO
    c1.member_age_years,
    c1.member_age_category,
    c1.member_gender,
    c1.member_city,
    c1.member_state,
    c1.member_zip5,
    c1.member_state_category,
    c1.member_occupation,
    c1.naics_occupation_code,
    c1.member_occupation_category,
    c1.member_tenure_years,
    c1.member_tenure_category,
    c1.collection_queue_id,
    c1.delinquency_status_code_id,
    c1.date_first_delinquent,
    c1.member_delinquency_history,
    c1.member_total_accounts,
    c1.member_engagement_level,
    c1.member_phone,
    c1.member_email,
    
    c1.balance,
    c1.next_payment_date,
    c1.days_delinquent         AS days_delinquent_m1,
    c1.Delinquency_Bracket     AS Delinquency_Bracket_m1,
    c1.credit_card,
    c1.desc_u,
    c1.cb_loan_type,
    c1.loan_main_category,
    c2.days_delinquent_m2,
    c2.Delinquency_Bracket_m2,

    /* Rank de cada mes */
    NULLIF(FIELD(
      c1.Delinquency_Bracket,
      '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'
    ),0)-1 AS rank_m1,

    NULLIF(FIELD(
      c2.Delinquency_Bracket_m2,
      '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'
    ),0)-1 AS rank_m2,

    /* Classification of change (English labels) */
    CASE
      WHEN c2.Delinquency_Bracket_m2 IS NULL THEN 'Loan Paid Off'
      WHEN FIELD(c2.Delinquency_Bracket_m2,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        > FIELD(c1.Delinquency_Bracket,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        THEN 'Deteriorated'
      WHEN FIELD(c2.Delinquency_Bracket_m2,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        = FIELD(c1.Delinquency_Bracket,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        THEN 'No Change'
      ELSE 'Improved'
    END AS delinquency_change,

    /* Deterioration flag (1 = deteriorated, 0 = everything else) */
    CASE
      WHEN c2.Delinquency_Bracket_m2 IS NULL THEN 0
      WHEN FIELD(c2.Delinquency_Bracket_m2,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        > FIELD(c1.Delinquency_Bracket,
                '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days')
        THEN 1
      ELSE 0
    END AS deterioration_flag,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: PORTFOLIO Y CONCENTRACIÓN
    -- ========================================================================
    COALESCE(mp.member_total_loans, 1) AS member_total_loans,
    COALESCE(mp.member_total_loan_balance, c1.balance) AS member_total_loan_balance,
    COALESCE(mp.member_total_delinquent_balance, 0) AS member_total_delinquent_balance,
    COALESCE(mp.member_worst_delinquency_days, c1.days_delinquent) AS member_worst_delinquency_days,
    COALESCE(mp.member_delinquent_loan_count, 0) AS member_delinquent_loan_count,
    COALESCE(mp.member_exposure_category, 'Unknown') AS member_exposure_category,
    COALESCE(mp.has_multiple_delinquent_loans, 0) AS has_multiple_delinquent_loans,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: ACCIONES DE COBRANZA
    -- ========================================================================
    COALESCE(ca.collection_contacts_90d, 0) AS collection_contacts_90d,
    COALESCE(ca.collection_contact_days_90d, 0) AS collection_contact_days_90d,
    COALESCE(ca.promises_made_90d, 0) AS promises_made_90d,
    COALESCE(ca.total_promise_amount_90d, 0) AS total_promise_amount_90d,
    COALESCE(ca.total_collected_90d, 0) AS total_collected_90d,
    ca.last_collection_contact_date,
    ca.days_since_last_contact,
    ca.last_collection_action,
    ca.last_collection_user,
    COALESCE(ca.pending_promises_next_30d, 0) AS pending_promises_next_30d,
    ca.collection_effectiveness_pct,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: COLLECTION QUEUE ACTUAL
    -- ========================================================================
    ccq.collection_queue_name,
    ccq.queue_min_days,
    ccq.queue_max_days,
    ccq.manually_added_to_queue,
    ccq.keep_in_current_queue,
    ccq.date_added_to_queue,
    ccq.days_in_current_queue,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: RECUPERACIÓN Y CHARGE-OFF
    -- ========================================================================
    COALESCE(rm.is_charged_off, 0) AS is_charged_off,
    rm.charge_off_date,
    rm.days_since_chargeoff,
    rm.chargeoff_original_principal,
    rm.chargeoff_current_principal,
    rm.recovered_principal,
    rm.recovered_interest,
    rm.recovered_fees,
    rm.total_recovered,
    rm.recovery_rate_pct,
    rm.chargeoff_status,
    rm.bankruptcy_status,
    rm.recovery_status,
    rm.chargeoff_last_payment_date,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: LOAN DEFERMENT STATUS
    -- ========================================================================
    COALESCE(lds.has_deferment, 0) AS has_loan_deferment,
    lds.deferment_start_date,
    lds.end_deferment_date,
    lds.deferment_status,
    lds.deferment_duration_days,
    lds.deferment_interest_accrued,
    lds.delinq_date_before_deferment,
    lds.account_status_prior_to_deferment,
    lds.deferment_created_date,
    lds.deferment_created_by,
    
    -- ========================================================================
    -- NUEVOS CAMPOS: PAYMENT ARRANGEMENTS (SKIP PAYMENTS)
    -- ========================================================================
    COALESCE(pa.total_skip_payments, 0) AS total_skip_payments,
    COALESCE(pa.total_extensions, 0) AS total_extensions,
    pa.last_skip_payment_date,
    COALESCE(pa.total_skip_fees, 0) AS total_skip_fees,
    COALESCE(pa.completed_skips, 0) AS completed_skips,
    COALESCE(pa.has_active_skip_payment, 0) AS has_active_skip_payment,
    pa.recent_skip_payment_date,
    COALESCE(pa.has_recent_skip_payment, 0) AS has_recent_skip_payment,
    
    -- ========================================================================
    -- ESTADO CONSOLIDADO DE DEFERMENT/SKIP
    -- ========================================================================
    CASE 
        WHEN lds.deferment_status IN ('Active Deferment', 'Active (No End Date)') 
            THEN 'DEFERRED (Active)'
        WHEN pa.has_active_skip_payment = 1 
            THEN 'SKIP PAYMENT (Active)'
        WHEN pa.has_recent_skip_payment = 1 
            THEN 'SKIP PAYMENT (Recent - Last 3 months)'
        WHEN lds.deferment_status = 'Recently Completed (<6 months)' 
            THEN 'DEFERRED (Recently Completed)'
        WHEN lds.has_deferment = 1 OR pa.total_skip_payments > 0 
            THEN 'Has Deferment/Skip History'
        ELSE 'No Deferment/Skip'
    END AS deferment_skip_consolidated_status,
    
    -- Flag combinado de cualquier tipo de deferment activo
    CASE 
        WHEN lds.deferment_status IN ('Active Deferment', 'Active (No End Date)')
            OR pa.has_active_skip_payment = 1
            OR pa.has_recent_skip_payment = 1
        THEN 1 ELSE 0 
    END AS has_any_active_deferment,
    
    -- ========================================================================
    -- NOTA SOBRE DÍAS DE MORA Y DEFERMENT:
    -- Los días de mora (days_delinquent_m1, days_delinquent_m2) ya están
    -- calculados correctamente basados en next_payment_date.
    -- 
    -- Cuando se aplica un SKIP PAYMENT:
    -- - El sistema automáticamente ajusta next_payment_date al nuevo mes
    -- - Por lo tanto, los días de mora se calculan contra la nueva fecha
    -- - NO es necesario ajustar manualmente los días de mora
    -- 
    -- Cuando se aplica un DEFERMENT tradicional (loan_deferment):
    -- - El sistema congela el préstamo durante el período de deferment
    -- - Durante deferment activo, el préstamo NO acumula días de mora
    -- - Después del deferment, el préstamo retoma su calendario normal
    -- 
    -- IMPORTANTE: Filtrar loans con deferment activo al analizar morosidad:
    -- WHERE has_any_active_deferment = 0
    -- ========================================================================
    
    -- ========================================================================
    -- MÉTRICAS AGREGADAS FIJAS - RESUMEN DE MOROSIDAD (CAMPOS CALCULADOS)
    -- ========================================================================
    sm1.total_loans_m1,
    sm1.total_balance_m1,
    sm1.delinquent_loans_m1,
    sm1.delinquent_balance_m1,
    sm1.pct_loans_delq_m1,
    sm1.pct_balance_delq_m1,
    
    sm2.total_loans_m2,
    sm2.total_balance_m2,
    sm2.delinquent_loans_m2,
    sm2.delinquent_balance_m2,
    sm2.pct_loans_delq_m2,
    sm2.pct_balance_delq_m2,
    
    -- CAMBIOS MES A MES
    (sm2.delinquent_balance_m2 - sm1.delinquent_balance_m1) AS change_delinquent_balance,
    (sm2.delinquent_loans_m2 - sm1.delinquent_loans_m1) AS change_delinquent_loans,
    (sm2.total_balance_m2 - sm1.total_balance_m1) AS change_total_balance,
    (sm2.total_loans_m2 - sm1.total_loans_m1) AS change_total_loans,
    
    -- CAMBIOS PORCENTUALES
    ROUND(((sm2.delinquent_balance_m2 - sm1.delinquent_balance_m1) / NULLIF(sm1.delinquent_balance_m1, 0)) * 100, 2) AS pct_change_delinquent_balance,
    ROUND(((sm2.delinquent_loans_m2 - sm1.delinquent_loans_m1) / NULLIF(sm1.delinquent_loans_m1, 0)) * 100, 2) AS pct_change_delinquent_loans

  FROM c1
  CROSS JOIN summary_m1 sm1
  CROSS JOIN summary_m2 sm2
  LEFT JOIN c2 ON c1.account_id = c2.account_id
  LEFT JOIN member_portfolio mp ON c1.member_number = mp.member_number
  LEFT JOIN collection_activity ca ON c1.account_id = ca.account_id
  LEFT JOIN current_collection_queue ccq ON c1.account_id = ccq.account_id
  LEFT JOIN recovery_metrics rm ON c1.account_id = rm.account_id
  LEFT JOIN loan_deferment_status lds ON c1.account_id = lds.account_id
  LEFT JOIN payment_arrangements pa ON c1.account_id = pa.account_id
ORDER BY c1.account_id