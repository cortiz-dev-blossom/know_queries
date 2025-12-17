-- ========================================================================
-- MWCU LOAN DELINQUENCY HISTORY - HISTORIAL DE MOROSIDAD (Athena/Presto)
-- Catalog: AwsDataCatalog.silver_know
-- Ajustes: Eliminado last_day() -> equivalente con date_trunc/date_add
-- ========================================================================

WITH monthly_data AS (
    SELECT
        -- Para clasificación FI
        a.credit_union,

        -- ID General único por período y préstamo
        concat(date_format(l.record_date, '%Y-%m'), '-', cast(l.account_id AS varchar)) AS ID_General,

        -- Información de período
        date_format(l.record_date, '%Y-%m') AS Period,
        l.record_date AS Date,

        -- Identificación del préstamo
        a.account_number AS Loan_Account_Number,
        l.account_id     AS Loan_ID,
        a.date_opened    AS Date_Loan_Opened,

        -- Información financiera
        l.balance AS Loan_Balance,

        -- % del balance total del mes
        l.balance / SUM(l.balance) OVER (PARTITION BY date_format(l.record_date, '%Y-%m')) AS Loan_Balance_Pct_Month,

        -- % del balance EN MORA del mes (solo si está en mora)
        CASE
            WHEN date_diff('day', l.next_payment_date, l.record_date) > 0 THEN
                l.balance /
                NULLIF(
                    SUM(CASE WHEN date_diff('day', l.next_payment_date, l.record_date) > 0 THEN l.balance ELSE 0 END)
                    OVER (PARTITION BY date_format(l.record_date, '%Y-%m'))
                , 0)
            ELSE NULL
        END AS Loan_Balance_Pct_Delinquent,

        -- Clasificación Credit Bureau
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

        -- Plazo
        al.number_of_payments AS Loan_Months_Term,

        -- ===============================
        -- INDICADORES DE PRIMER PAGO VENCIDO Y NO REALIZADO
        -- ===============================
        CASE
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 1
            ELSE 0
        END AS Missed_First_Payment_Flag,

        CASE
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 'Missed First Payment (Overdue)'
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) = 0 THEN 'Due Today (Not Paid Yet)'
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) < 0 THEN 'No Payment Yet (Not Due)'
            WHEN al.last_payment_date IS NOT NULL THEN 'Has Made Payment(s)'
            ELSE 'Unknown'
        END AS First_Payment_Status,

        -- Días vencidos del primer pago sin realizar
        CASE
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) >= 1
            THEN date_diff('day', l.next_payment_date, l.record_date)
            ELSE NULL
        END AS Days_Overdue_First_Payment,

        -- Último pago
        al.last_payment_date AS Last_Payment_Date,

        -- Días de mora (no negativos)
        CASE
            WHEN date_diff('day', l.next_payment_date, l.record_date) < 0 THEN 0
            ELSE date_diff('day', l.next_payment_date, l.record_date)
        END AS Days_Delinquency,

        -- Bracket de mora (incluye FPD)
        CASE
            WHEN al.last_payment_date IS NULL
             AND l.next_payment_date IS NOT NULL
             AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 'First Payment Delinquency'
            WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 1 AND 30 THEN '1-30 days'
            WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 31 AND 60 THEN '31-60 days'
            WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 61 AND 90 THEN '61-90 days'
            WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 91 AND 120 THEN '91-120 days'
            WHEN date_diff('day', l.next_payment_date, l.record_date) > 120 THEN 'Over 120 days'
            ELSE '0 days'
        END AS Bracket_Delinquency,

        -- Rank del bracket (FIELD -> array_position)
        (coalesce(
            array_position(
                ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'],
                CASE
                    WHEN al.last_payment_date IS NULL
                     AND l.next_payment_date IS NOT NULL
                     AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 'First Payment Delinquency'
                    WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 1 AND 30 THEN '1-30 days'
                    WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 31 AND 60 THEN '31-60 days'
                    WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 61 AND 90 THEN '61-90 days'
                    WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 91 AND 120 THEN '91-120 days'
                    WHEN date_diff('day', l.next_payment_date, l.record_date) > 120 THEN 'Over 120 days'
                    ELSE '0 days'
                END
            ), 0) - 1
        ) AS current_rank,

        -- Credit / Risk
        al.credit_score AS Credit_Score,

        -- Próximo pago
        l.next_payment_date AS Next_Payment_Date,

        -- Miembro
        m.member_entity_id AS Member_ID,
        a.member_number    AS Member_Number,

        -- Contacto
        pn.phone_number AS Member_Phone,
        e.email1       AS Member_Email,

        -- Demografía
        CASE
            WHEN e.gender = 'M' THEN 'Male'
            WHEN e.gender = 'F' THEN 'Female'
            WHEN e.gender = 'O' THEN 'Other'
            WHEN e.gender = '' OR e.gender IS NULL THEN 'Unknown'
            ELSE 'Other'
        END AS Member_Gender,

        CASE
            WHEN e.dob IS NULL THEN 'Age Unknown'
            WHEN date_diff('year', e.dob, l.record_date) < 25 THEN 'Under 25'
            WHEN date_diff('year', e.dob, l.record_date) BETWEEN 25 AND 34 THEN '25-34 years'
            WHEN date_diff('year', e.dob, l.record_date) BETWEEN 35 AND 44 THEN '35-44 years'
            WHEN date_diff('year', e.dob, l.record_date) BETWEEN 45 AND 54 THEN '45-54 years'
            WHEN date_diff('year', e.dob, l.record_date) BETWEEN 55 AND 64 THEN '55-64 years'
            WHEN date_diff('year', e.dob, l.record_date) BETWEEN 65 AND 74 THEN '65-74 years'
            WHEN date_diff('year', e.dob, l.record_date) >= 75 THEN '75+ years'
            ELSE 'Age Unknown'
        END AS Member_Age_Category,

        CASE
            WHEN m.join_date IS NULL THEN 'Unknown Tenure'
            WHEN date_diff('year', m.join_date, l.record_date) < 1 THEN 'New Member (<1 year)'
            WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 1 AND 2 THEN 'Recent Member (1-2 years)'
            WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 3 AND 5 THEN 'Established Member (3-5 years)'
            WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 6 AND 10 THEN 'Long-term Member (6-10 years)'
            WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 11 AND 20 THEN 'Veteran Member (11-20 years)'
            WHEN date_diff('year', m.join_date, l.record_date) > 20 THEN 'Legacy Member (20+ years)'
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
        CASE WHEN ld.account_id IS NOT NULL THEN 1 ELSE 0 END AS Has_Loan_Deferment,

        ld.start_date         AS Deferment_Start_Date,
        ld.end_deferment_date AS Deferment_End_Date,

        CASE
            WHEN ld.end_deferment_date IS NULL THEN 'Active (No End Date)'
            WHEN ld.end_deferment_date >= l.record_date THEN 'Active Deferment'
            WHEN ld.end_deferment_date <  l.record_date
             AND ld.end_deferment_date >= date_add('month', -6, l.record_date) THEN 'Recently Completed (<6 months)'
            WHEN ld.end_deferment_date <  date_add('month', -6, l.record_date) THEN 'Historical Deferment (>6 months ago)'
            ELSE NULL
        END AS Deferment_Status,

        CASE
            WHEN ld.end_deferment_date IS NULL AND ld.start_date IS NOT NULL
                THEN date_diff('day', ld.start_date, l.record_date)
            WHEN ld.end_deferment_date IS NOT NULL AND ld.start_date IS NOT NULL
                THEN date_diff('day', ld.start_date, ld.end_deferment_date)
            ELSE NULL
        END AS Deferment_Duration_Days,

        -- ===============================
        -- SKIP PAYMENT STATUS (Histórico) - subconsultas correlacionadas
        -- ===============================
        (SELECT COUNT(*)
         FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_count
         WHERE lsp_count.account_id = l.account_id
           AND lsp_count.credit_union = l.credit_union
           AND lsp_count.payment_to_skip <= l.record_date
        ) AS Total_Skip_Payments,

        (SELECT SUM(lsp_fee.fee_amount)
         FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_fee
         WHERE lsp_fee.account_id = l.account_id
           AND lsp_fee.credit_union = l.credit_union
           AND lsp_fee.payment_to_skip <= l.record_date
        ) AS Total_Skip_Fees,

        (SELECT MAX(lsp_max.payment_to_skip)
         FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_max
         WHERE lsp_max.account_id = l.account_id
           AND lsp_max.credit_union = l.credit_union
           AND lsp_max.payment_to_skip <= l.record_date
        ) AS Last_Skip_Payment_Date,

        (SELECT MAX(CASE WHEN lsp_active.skip_completed = 0
                          AND lsp_active.payment_to_skip >= l.record_date
                     THEN 1 ELSE 0 END)
         FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_active
         WHERE lsp_active.account_id = l.account_id
           AND lsp_active.credit_union = l.credit_union
        ) AS Has_Active_Skip_Payment,

        CASE WHEN EXISTS (
            SELECT 1
            FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_recent
            WHERE lsp_recent.account_id = l.account_id
              AND lsp_recent.credit_union = l.credit_union
              AND lsp_recent.payment_to_skip >= date_add('month', -3, l.record_date)
              AND lsp_recent.payment_to_skip <= l.record_date
        ) THEN 1 ELSE 0 END AS Has_Recent_Skip_Payment,

        (SELECT MAX(lsp_rec.payment_to_skip)
         FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_rec
         WHERE lsp_rec.account_id = l.account_id
           AND lsp_rec.credit_union = l.credit_union
           AND lsp_rec.payment_to_skip >= date_add('month', -3, l.record_date)
           AND lsp_rec.payment_to_skip <= l.record_date
        ) AS Recent_Skip_Payment_Date,

        CASE
            WHEN ld.account_id IS NOT NULL
             AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date)
                THEN 'DEFERRED (Active)'
            WHEN (SELECT MAX(CASE WHEN lsp_active2.skip_completed = 0
                                    AND lsp_active2.payment_to_skip >= l.record_date
                               THEN 1 ELSE 0 END)
                  FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_active2
                  WHERE lsp_active2.account_id   = l.account_id
                    AND lsp_active2.credit_union = l.credit_union) = 1
                THEN 'SKIP PAYMENT (Active)'
            WHEN EXISTS (
                SELECT 1
                FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_recent2
                WHERE lsp_recent2.account_id   = l.account_id
                  AND lsp_recent2.credit_union = l.credit_union
                  AND lsp_recent2.payment_to_skip >= date_add('month', -3, l.record_date)
                  AND lsp_recent2.payment_to_skip <= l.record_date
            ) THEN 'SKIP PAYMENT (Recent - Last 3 months)'
            WHEN ld.account_id IS NOT NULL
             AND ld.end_deferment_date < l.record_date
             AND ld.end_deferment_date >= date_add('month', -6, l.record_date)
                THEN 'DEFERRED (Recently Completed)'
            WHEN ld.account_id IS NOT NULL
                OR (SELECT COUNT(*)
                    FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_hist
                    WHERE lsp_hist.account_id   = l.account_id
                      AND lsp_hist.credit_union = l.credit_union
                      AND lsp_hist.payment_to_skip <= l.record_date) > 0
                THEN 'Has Deferment/Skip History'
            ELSE 'No Deferment/Skip'
        END AS Deferment_Skip_Status,

        CASE
            WHEN (ld.account_id IS NOT NULL AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date))
              OR (SELECT MAX(CASE WHEN lsp_active3.skip_completed = 0
                                   AND lsp_active3.payment_to_skip >= l.record_date
                              THEN 1 ELSE 0 END)
                  FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_active3
                  WHERE lsp_active3.account_id   = l.account_id
                    AND lsp_active3.credit_union = l.credit_union) = 1
              OR EXISTS (
                    SELECT 1
                    FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp_recent3
                    WHERE lsp_recent3.account_id   = l.account_id
                      AND lsp_recent3.credit_union = l.credit_union
                      AND lsp_recent3.payment_to_skip >= date_add('month', -3, l.record_date)
                      AND lsp_recent3.payment_to_skip <= l.record_date
                )
            THEN 1 ELSE 0
        END AS Has_Any_Active_Deferment

    FROM "AwsDataCatalog"."silver_know"."eom_loan" l
    JOIN "AwsDataCatalog"."silver_know"."account" a
      ON a.account_id    = l.account_id
     AND a.credit_union  = l.credit_union
    JOIN "AwsDataCatalog"."silver_know"."account_loan" al
      ON al.account_id   = a.account_id
     AND al.credit_union = a.credit_union
    JOIN "AwsDataCatalog"."silver_know"."account_types" t
      ON t.account_type  = l.account_type
     AND t.credit_union  = l.credit_union
    JOIN "AwsDataCatalog"."silver_know"."member" m
      ON a.member_number = m.member_number
     AND a.credit_union  = m.credit_union
    JOIN "AwsDataCatalog"."silver_know"."entity" e
      ON m.member_entity_id = e.entity_id
     AND m.credit_union     = e.credit_union
    LEFT JOIN "AwsDataCatalog"."silver_know"."phone_number" pn
      ON e.entity_id    = pn.entity_id
     AND e.credit_union = pn.credit_union
     AND pn.primary_phone = 1
    LEFT JOIN "AwsDataCatalog"."silver_know"."loan_deferment" ld
      ON l.account_id   = ld.account_id
     AND l.credit_union = ld.credit_union
     AND ld.start_date <= l.record_date
     AND (ld.end_deferment_date IS NULL OR ld.end_deferment_date >= l.record_date)
    WHERE
        -- Últimos 6 meses completos (fin de cada mes):
        -- prev_month_end = first_day_current_month - 1
        l.record_date >= date_add('month', -11, date_add('day', -1, date_trunc('month', current_date)))
        AND l.record_date <= date_add('day', -1, date_trunc('month', current_date))
        -- Solo fin de mes: end_of_month(d) = date_add('day', -1, date_trunc('month', date_add('month', 1, d)))
        AND l.record_date = date_add('day', -1, date_trunc('month', date_add('month', 1, l.record_date)))
        -- Solo préstamos activos
        AND l.date_closed IS NULL
        AND l.balance > 0
        AND coalesce(a.current_balance, l.balance) > 0
        -- Excluir tarjetas de crédito
        AND coalesce(t.credit_card, 'N') NOT IN ('Y','X','1')
),
previous_month_data AS (
    SELECT
        md.Loan_ID,
        md.Period,
        md.current_rank,
        md.Bracket_Delinquency,
        LAG(md.current_rank)        OVER (PARTITION BY md.Loan_ID ORDER BY md.Period) AS prev_rank,
        LAG(md.Bracket_Delinquency) OVER (PARTITION BY md.Loan_ID ORDER BY md.Period) AS prev_bracket
    FROM monthly_data md
)
SELECT
    -- Clasificación FI
    md.credit_union                 AS credit_union,
    fi.idfi                         AS idFi,
    ci.credit_union_name            AS CU_Name,

    -- Output solicitado
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

    -- FIRST PAYMENT DELINQUENCY
    md.Missed_First_Payment_Flag,
    md.First_Payment_Status,
    md.Days_Overdue_First_Payment,
    md.Last_Payment_Date,

    -- DELINQUENCY
    md.Days_Delinquency,
    md.Bracket_Delinquency,

    -- Cambio vs mes anterior
    CASE
        WHEN pmd.prev_rank IS NULL          THEN 'New Loan'
        WHEN md.current_rank > pmd.prev_rank THEN 'Deteriorated'
        WHEN md.current_rank = pmd.prev_rank THEN 'No Change'
        WHEN md.current_rank < pmd.prev_rank THEN 'Improved'
        ELSE 'Unknown'
    END AS Status_Loan_Change,

    -- DEFERMENT / SKIP
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

    -- CREDIT / RISK
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
 AND md.Period  = pmd.Period

-- JOINS de clasificación FI
LEFT JOIN "AwsDataCatalog"."silver_know"."blossomcompany_olb_map" fi
  ON lower(trim(fi.prodigy_code)) = lower(trim(md.credit_union))
LEFT JOIN "AwsDataCatalog"."silver_know"."credit_union_info" ci
  ON ci.credit_union   = md.credit_union
 AND ci.flag_inactive <> 'Y'

ORDER BY md.Period DESC, md.Loan_ID;
--LIMIT 10;
