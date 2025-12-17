-- ========================================================================
-- MWCU LOAN DELINQUENCY HISTORY - HISTORIAL DE MOROSIDAD
-- Business Purpose: Seguimiento histórico mensual del comportamiento de loans en mora
-- Created: 28 de noviembre de 2025
-- Database: MINNEQUA WORKS CREDIT UNION (mwcu schema)
-- Período: Últimos 6 meses completos
-- ========================================================================

WITH monthly_data AS (
    SELECT
        -- ID General único por período y préstamo
        CONCAT(DATE_FORMAT(l.record_date, '%Y-%m'), '-', l.account_id) AS ID_General,
        
        -- Información de período
        DATE_FORMAT(l.record_date, '%Y-%m') AS Period,
        l.record_date AS Date,
        
        -- Identificación del préstamo
        a.account_number AS Loan_Account_Number,
        l.account_id AS Loan_ID,
        a.date_opened AS Date_Loan_Opened,
        
        -- Información financiera
        l.balance AS Loan_Balance,
        
        -- Porcentaje del balance total del mes (como decimal: 0.01 = 1%)
        l.balance / SUM(l.balance) OVER (PARTITION BY DATE_FORMAT(l.record_date, '%Y-%m')) AS Loan_Balance_Pct_Month,
        
        -- Porcentaje del balance EN MORA del mes (como decimal: 0.01 = 1%)
        -- Solo calcula para loans en mora, NULL para loans al corriente
        CASE 
            WHEN DATEDIFF(l.record_date, l.next_payment_date) > 0 THEN
                l.balance / NULLIF(SUM(CASE WHEN DATEDIFF(l.record_date, l.next_payment_date) > 0 THEN l.balance ELSE 0 END) 
                    OVER (PARTITION BY DATE_FORMAT(l.record_date, '%Y-%m')), 0)
            ELSE NULL
        END AS Loan_Balance_Pct_Delinquent,
        
        -- Clasificación del préstamo basada en Credit Bureau
        t.cb_loan_type,
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
        END AS Loan_Main_Category,
        
        -- Plazo del préstamo en meses
        al.number_of_payments AS Loan_Months_Term,
        
        -- ===============================
        -- INDICADORES DE PRIMER PAGO VENCIDO Y NO REALIZADO
        -- ===============================
        CASE 
            WHEN al.last_payment_date IS NULL 
                AND l.next_payment_date IS NOT NULL
                AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
            THEN 1
            ELSE 0
        END AS Missed_First_Payment_Flag,
        
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
        END AS First_Payment_Status,
        
        -- Días vencidos del primer pago sin realizar
        CASE 
            WHEN al.last_payment_date IS NULL 
                AND l.next_payment_date IS NOT NULL
                AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
            THEN DATEDIFF(l.record_date, l.next_payment_date)
            ELSE NULL
        END AS Days_Overdue_First_Payment,
        
        -- Fecha del último pago realizado
        al.last_payment_date AS Last_Payment_Date,
        
        -- Cálculo de días de morosidad
        IF(DATEDIFF(l.record_date, l.next_payment_date) < 0, 0,
           DATEDIFF(l.record_date, l.next_payment_date)) AS Days_Delinquency,
        
        -- Bracket de morosidad INCLUYENDO First Payment Delinquency
        CASE 
            WHEN al.last_payment_date IS NULL 
                AND l.next_payment_date IS NOT NULL
                AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
            THEN 'First Payment Delinquency'
            WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 1 AND 30  THEN '1-30 days'
            WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 31 AND 60 THEN '31-60 days'
            WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 61 AND 90 THEN '61-90 days'
            WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 91 AND 120 THEN '91-120 days'
            WHEN DATEDIFF(l.record_date, l.next_payment_date) > 120 THEN 'Over 120 days'
            ELSE '0 days'
        END AS Bracket_Delinquency,
        
        -- Rank del bracket para comparaciones (INCLUYENDO First Payment Delinquency)
        NULLIF(FIELD(
            CASE 
                WHEN al.last_payment_date IS NULL 
                    AND l.next_payment_date IS NOT NULL
                    AND DATEDIFF(l.record_date, l.next_payment_date) >= 1 
                THEN 'First Payment Delinquency'
                WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 1 AND 30  THEN '1-30 days'
                WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 31 AND 60 THEN '31-60 days'
                WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 61 AND 90 THEN '61-90 days'
                WHEN DATEDIFF(l.record_date, l.next_payment_date) BETWEEN 91 AND 120 THEN '91-120 days'
                WHEN DATEDIFF(l.record_date, l.next_payment_date) > 120 THEN 'Over 120 days'
                ELSE '0 days'
            END,
            '0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'
        ), 0) - 1 AS current_rank,
        
        -- Credit Score
        al.credit_score AS Credit_Score,
        
        -- Fecha de próximo pago
        l.next_payment_date AS Next_Payment_Date,
        
        -- Información del miembro
        m.member_entity_id AS Member_ID,
        a.member_number AS Member_Number,
        
        -- Información de contacto del miembro
        pn.phone_number AS Member_Phone,
        e.email1 AS Member_Email,
        
        -- Información demográfica adicional
        CASE 
            WHEN e.gender = 'M' THEN 'Male'
            WHEN e.gender = 'F' THEN 'Female'
            WHEN e.gender = 'O' THEN 'Other'
            WHEN e.gender = '' OR e.gender IS NULL THEN 'Unknown'
            ELSE 'Other'
        END AS Member_Gender,
        
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
        END AS Member_Age_Category,
        
        CASE 
            WHEN m.join_date IS NULL THEN 'Unknown Tenure'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) < 1 THEN 'New Member (<1 year)'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 1 AND 2 THEN 'Recent Member (1-2 years)'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 3 AND 5 THEN 'Established Member (3-5 years)'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 6 AND 10 THEN 'Long-term Member (6-10 years)'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) BETWEEN 11 AND 20 THEN 'Veteran Member (11-20 years)'
            WHEN TIMESTAMPDIFF(YEAR, m.join_date, l.record_date) > 20 THEN 'Legacy Member (20+ years)'
            ELSE 'Unknown Tenure'
        END AS Member_Tenure_Category,
        
        al.credit_score_code AS Credit_Score_Code,
        
        CASE 
            WHEN al.interest_rate <= 5.00 THEN 'Prime (≤5%)'
            WHEN al.interest_rate BETWEEN 5.01 AND 8.00 THEN 'Near-Prime (5-8%)'
            WHEN al.interest_rate BETWEEN 8.01 AND 12.00 THEN 'Standard (8-12%)'
            WHEN al.interest_rate BETWEEN 12.01 AND 18.00 THEN 'Subprime (12-18%)'
            WHEN al.interest_rate > 18.00 THEN 'High-Risk (>18%)'
            ELSE 'No Rate Data'
        END AS Interest_Rate_Category,
        
        -- ===============================
        -- LOAN DEFERMENT STATUS (Histórico)
        -- ===============================
        CASE 
            WHEN ld.account_id IS NOT NULL THEN 1 
            ELSE 0 
        END AS Has_Loan_Deferment,
        
        ld.start_date AS Deferment_Start_Date,
        ld.end_deferment_date AS Deferment_End_Date,
        
        CASE 
            WHEN ld.end_deferment_date IS NULL THEN 'Active (No End Date)'
            WHEN ld.end_deferment_date >= l.record_date THEN 'Active Deferment'
            WHEN ld.end_deferment_date < l.record_date 
                AND ld.end_deferment_date >= DATE_SUB(l.record_date, INTERVAL 6 MONTH) 
                THEN 'Recently Completed (<6 months)'
            WHEN ld.end_deferment_date < DATE_SUB(l.record_date, INTERVAL 6 MONTH)
                THEN 'Historical Deferment (>6 months ago)'
            ELSE NULL
        END AS Deferment_Status,
        
        CASE 
            WHEN ld.end_deferment_date IS NULL AND ld.start_date IS NOT NULL
                THEN DATEDIFF(l.record_date, ld.start_date)
            WHEN ld.end_deferment_date IS NOT NULL AND ld.start_date IS NOT NULL
                THEN DATEDIFF(ld.end_deferment_date, ld.start_date)
            ELSE NULL
        END AS Deferment_Duration_Days,
        
        -- ===============================
        -- SKIP PAYMENT STATUS (Histórico)
        -- ===============================
        (SELECT COUNT(*) 
         FROM loan_skip_payment lsp_count 
         WHERE lsp_count.account_id = l.account_id 
           AND lsp_count.payment_to_skip <= l.record_date
        ) AS Total_Skip_Payments,
        
        (SELECT SUM(lsp_fee.fee_amount) 
         FROM loan_skip_payment lsp_fee 
         WHERE lsp_fee.account_id = l.account_id 
           AND lsp_fee.payment_to_skip <= l.record_date
        ) AS Total_Skip_Fees,
        
        (SELECT MAX(lsp_max.payment_to_skip) 
         FROM loan_skip_payment lsp_max 
         WHERE lsp_max.account_id = l.account_id 
           AND lsp_max.payment_to_skip <= l.record_date
        ) AS Last_Skip_Payment_Date,
        
        -- Skip payment activo o futuro en el período analizado
        (SELECT MAX(CASE WHEN lsp_active.skip_completed = 0 
                         AND lsp_active.payment_to_skip >= l.record_date 
                    THEN 1 ELSE 0 END)
         FROM loan_skip_payment lsp_active 
         WHERE lsp_active.account_id = l.account_id
        ) AS Has_Active_Skip_Payment,
        
        -- Skip payment reciente (últimos 3 meses desde el período analizado)
        CASE WHEN EXISTS (
            SELECT 1 FROM loan_skip_payment lsp_recent 
            WHERE lsp_recent.account_id = l.account_id 
              AND lsp_recent.payment_to_skip >= DATE_SUB(l.record_date, INTERVAL 3 MONTH)
              AND lsp_recent.payment_to_skip <= l.record_date
        ) THEN 1 ELSE 0 END AS Has_Recent_Skip_Payment,
        
        (SELECT MAX(lsp_rec.payment_to_skip) 
         FROM loan_skip_payment lsp_rec 
         WHERE lsp_rec.account_id = l.account_id 
           AND lsp_rec.payment_to_skip >= DATE_SUB(l.record_date, INTERVAL 3 MONTH)
           AND lsp_rec.payment_to_skip <= l.record_date
        ) AS Recent_Skip_Payment_Date,
        
        -- Estado consolidado de Deferment/Skip
        CASE 
            WHEN ld.account_id IS NOT NULL AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date)
                THEN 'DEFERRED (Active)'
            WHEN (SELECT MAX(CASE WHEN lsp_active2.skip_completed = 0 
                              AND lsp_active2.payment_to_skip >= l.record_date 
                         THEN 1 ELSE 0 END)
                  FROM loan_skip_payment lsp_active2 
                  WHERE lsp_active2.account_id = l.account_id) = 1
                THEN 'SKIP PAYMENT (Active)'
            WHEN EXISTS (
                SELECT 1 FROM loan_skip_payment lsp_recent2 
                WHERE lsp_recent2.account_id = l.account_id 
                  AND lsp_recent2.payment_to_skip >= DATE_SUB(l.record_date, INTERVAL 3 MONTH)
                  AND lsp_recent2.payment_to_skip <= l.record_date
            ) THEN 'SKIP PAYMENT (Recent - Last 3 months)'
            WHEN ld.account_id IS NOT NULL AND ld.end_deferment_date < l.record_date 
                AND ld.end_deferment_date >= DATE_SUB(l.record_date, INTERVAL 6 MONTH)
                THEN 'DEFERRED (Recently Completed)'
            WHEN ld.account_id IS NOT NULL 
                OR (SELECT COUNT(*) FROM loan_skip_payment lsp_hist 
                    WHERE lsp_hist.account_id = l.account_id 
                      AND lsp_hist.payment_to_skip <= l.record_date) > 0
                THEN 'Has Deferment/Skip History'
            ELSE 'No Deferment/Skip'
        END AS Deferment_Skip_Status,
        
        -- Flag combinado de cualquier deferment activo en el período
        CASE 
            WHEN (ld.account_id IS NOT NULL AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date))
                OR (SELECT MAX(CASE WHEN lsp_active3.skip_completed = 0 
                                AND lsp_active3.payment_to_skip >= l.record_date 
                           THEN 1 ELSE 0 END)
                    FROM loan_skip_payment lsp_active3 
                    WHERE lsp_active3.account_id = l.account_id) = 1
                OR EXISTS (
                    SELECT 1 FROM loan_skip_payment lsp_recent3 
                    WHERE lsp_recent3.account_id = l.account_id 
                      AND lsp_recent3.payment_to_skip >= DATE_SUB(l.record_date, INTERVAL 3 MONTH)
                      AND lsp_recent3.payment_to_skip <= l.record_date
                )
            THEN 1 ELSE 0 
        END AS Has_Any_Active_Deferment
        
    FROM eom_loan l
    JOIN account a ON a.account_id = l.account_id
    JOIN account_loan al ON a.account_id = al.account_id
    JOIN account_types t ON t.account_type = l.account_type
    JOIN member m ON a.member_number = m.member_number
    JOIN entity e ON m.member_entity_id = e.entity_id
    LEFT JOIN phone_number pn ON e.entity_id = pn.entity_id AND pn.primary_phone = 1
    LEFT JOIN loan_deferment ld ON l.account_id = ld.account_id 
        AND ld.start_date <= l.record_date
        AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date)
    WHERE 
        -- Últimos 6 meses completos (fin de cada mes)
        l.record_date >= DATE_SUB(LAST_DAY(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)), INTERVAL 11 MONTH)
        AND l.record_date <= LAST_DAY(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        -- Solo registros de fin de mes
        AND l.record_date = LAST_DAY(l.record_date)
        -- Solo préstamos activos
        AND l.date_closed IS NULL
        AND l.balance > 0
        AND COALESCE(a.current_balance, l.balance) > 0
        -- Excluir tarjetas de crédito
        AND COALESCE(t.credit_card,'N') NOT IN ('Y','X','1')
),
previous_month_data AS (
    SELECT
        md.Loan_ID,
        md.Period,
        md.current_rank,
        md.Bracket_Delinquency,
        -- Obtener el rank del mes anterior usando LAG
        LAG(md.current_rank) OVER (PARTITION BY md.Loan_ID ORDER BY md.Period) AS prev_rank,
        LAG(md.Bracket_Delinquency) OVER (PARTITION BY md.Loan_ID ORDER BY md.Period) AS prev_bracket
    FROM monthly_data md
)
SELECT
    md.ID_General,
    md.Period,
    md.Date,
    md.Loan_Account_Number,
    md.Loan_ID,
    md.Date_Loan_Opened,
    md.Loan_Balance,
    md.Loan_Balance_Pct_Month,
    md.Loan_Balance_Pct_Delinquent,
    md.Loan_Main_Category,
    md.Loan_Months_Term,
    
    -- ===============================
    -- FIRST PAYMENT DELINQUENCY
    -- ===============================
    md.Missed_First_Payment_Flag,
    md.First_Payment_Status,
    md.Days_Overdue_First_Payment,
    md.Last_Payment_Date,
    
    -- ===============================
    -- DELINQUENCY METRICS
    -- ===============================
    md.Days_Delinquency,
    md.Bracket_Delinquency,
    
    -- Status Loan Change comparado con el mes anterior
    CASE
        WHEN pmd.prev_rank IS NULL THEN 'New Loan'
        WHEN md.current_rank > pmd.prev_rank THEN 'Deteriorated'
        WHEN md.current_rank = pmd.prev_rank THEN 'No Change'
        WHEN md.current_rank < pmd.prev_rank THEN 'Improved'
        ELSE 'Unknown'
    END AS Status_Loan_Change,
    
    -- ===============================
    -- DEFERMENT AND SKIP PAYMENT STATUS
    -- ===============================
    md.Has_Loan_Deferment,
    md.Deferment_Start_Date,
    md.Deferment_End_Date,
    md.Deferment_Status,
    md.Deferment_Duration_Days,
    md.Total_Skip_Payments,
    md.Total_Skip_Fees,
    md.Last_Skip_Payment_Date,
    md.Has_Active_Skip_Payment,
    md.Has_Recent_Skip_Payment,
    md.Recent_Skip_Payment_Date,
    md.Deferment_Skip_Status,
    md.Has_Any_Active_Deferment,
    
    -- ===============================
    -- CREDIT AND RISK METRICS
    -- ===============================
    md.Credit_Score,
    md.Credit_Score_Code,
    md.Interest_Rate_Category,
    md.Next_Payment_Date,
    md.Member_ID,
    md.Member_Number,
    md.Member_Phone,
    md.Member_Email,
    md.Member_Gender,
    md.Member_Age_Category,
    md.Member_Tenure_Category

FROM monthly_data md
LEFT JOIN previous_month_data pmd 
    ON md.Loan_ID = pmd.Loan_ID 
    AND md.Period = pmd.Period

ORDER BY md.Period DESC, md.Loan_ID