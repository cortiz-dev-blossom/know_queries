WITH date_params AS (
    SELECT
        last_day(date_add('month', -1, current_date)) AS current_month_end,
        last_day(date_add('month', -2, current_date)) AS previous_month_end
),
base AS (
    SELECT
        a.credit_union,
        l.record_date,
        date_format(l.record_date, '%Y-%m') AS record_ym,
        a.member_number,
        a.account_number,
        a.account_id,
        al.credit_score,
        al.credit_score_code,
        a.date_opened,
        l.balance,
        l.next_payment_date,

        -- Loan age (months)
        CASE WHEN a.date_opened IS NOT NULL THEN
            date_diff('month', a.date_opened, l.record_date)
        ELSE NULL END AS loan_age_months,

        CASE
          WHEN a.date_opened IS NULL THEN 'No Account Data'
          WHEN date_diff('month', a.date_opened, l.record_date) <= 6 THEN '0-6 months'
          WHEN date_diff('month', a.date_opened, l.record_date) BETWEEN 7 AND 12 THEN '7-12 months'
          WHEN date_diff('month', a.date_opened, l.record_date) BETWEEN 13 AND 24 THEN '13-24 months'
          WHEN date_diff('month', a.date_opened, l.record_date) BETWEEN 25 AND 36 THEN '25-36 months'
          WHEN date_diff('month', a.date_opened, l.record_date) BETWEEN 37 AND 60 THEN '37-60 months'
          WHEN date_diff('month', a.date_opened, l.record_date) > 60 THEN 'Over 60 months'
          ELSE 'Unknown'
        END AS loan_age_category,

        al.number_of_payments AS original_loan_term_months,
        al.payments_per_year,
        al.maturity_date,

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

        al.opening_balance AS original_loan_amount,
        al.highest_balance_attained,
        al.interest_rate,
        al.payment_periodic AS scheduled_payment,
        al.amount_delq AS delinquent_amount,
        al.last_payment_date,
        al.interest_accumulated,
        al.principal_and_interest,

        -- Missed first payment flags
        CASE
          WHEN al.last_payment_date IS NULL
           AND l.next_payment_date IS NOT NULL
           AND date_diff('day', l.next_payment_date, l.record_date) >= 1
          THEN 1 ELSE 0 END AS missed_first_payment_flag,

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
        END AS first_payment_status,

        CASE
          WHEN al.last_payment_date IS NULL
           AND l.next_payment_date IS NOT NULL
           AND date_diff('day', l.next_payment_date, l.record_date) >= 1
          THEN date_diff('day', l.next_payment_date, l.record_date)
          ELSE NULL
        END AS days_overdue_first_payment,

        CASE
          WHEN al.last_payment_date IS NULL
           AND l.next_payment_date IS NOT NULL
           AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN
             CASE
               WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 1 AND 30  THEN 'Missed 1-30 days'
               WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 31 AND 60 THEN 'Missed 31-60 days'
               WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 61 AND 90 THEN 'Missed 61-90 days'
               WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 91 AND 120 THEN 'Missed 91-120 days'
               WHEN date_diff('day', l.next_payment_date, l.record_date) > 120 THEN 'Missed Over 120 days (Critical)'
               ELSE 'Unknown'
             END
          WHEN al.last_payment_date IS NULL
           AND l.next_payment_date IS NOT NULL
           AND date_diff('day', l.next_payment_date, l.record_date) = 0 THEN 'Due Today'
          WHEN al.last_payment_date IS NULL
           AND l.next_payment_date IS NOT NULL
           AND date_diff('day', l.next_payment_date, l.record_date) < 0 THEN 'Not Due Yet'
          WHEN al.last_payment_date IS NOT NULL THEN 'Has Made Payments'
          ELSE 'No Date Data'
        END AS first_payment_overdue_category,

        -- Risk ratios
        CASE WHEN al.opening_balance > 0 THEN (l.balance / al.opening_balance) * 100 ELSE NULL END AS loan_utilization_pct,
        CASE WHEN al.opening_balance > 0 THEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 ELSE NULL END AS loan_paydown_pct,
        CASE WHEN l.balance > 0 AND al.payment_periodic > 0 THEN (al.payment_periodic / l.balance) * 100 ELSE NULL END AS payment_to_balance_ratio,
        CASE WHEN al.number_of_payments > 0 THEN (date_diff('month', a.date_opened, l.record_date) / al.number_of_payments) * 100 ELSE NULL END AS loan_progress_pct,

        -- Amount category
        CASE
          WHEN al.opening_balance <= 5000 THEN 'Micro ($0-$5K)'
          WHEN al.opening_balance BETWEEN 5001 AND 15000 THEN 'Small ($5K-$15K)'
          WHEN al.opening_balance BETWEEN 15001 AND 50000 THEN 'Medium ($15K-$50K)'
          WHEN al.opening_balance BETWEEN 50001 AND 100000 THEN 'Large ($50K-$100K)'
          WHEN al.opening_balance > 100000 THEN 'Jumbo ($100K+)'
          ELSE 'No Amount Data'
        END AS loan_amount_category,

        -- Rate category
        CASE
          WHEN al.interest_rate <= 5.00 THEN 'Prime (≤5%)'
          WHEN al.interest_rate BETWEEN 5.01 AND 8.00 THEN 'Near-Prime (5-8%)'
          WHEN al.interest_rate BETWEEN 8.01 AND 12.00 THEN 'Standard (8-12%)'
          WHEN al.interest_rate BETWEEN 12.01 AND 18.00 THEN 'Subprime (12-18%)'
          WHEN al.interest_rate > 18.00 THEN 'High-Risk (>18%)'
          ELSE 'No Rate Data'
        END AS interest_rate_category,

        -- Categorized ratios
        CASE
          WHEN al.opening_balance = 0 THEN 'No Data'
          WHEN (l.balance / al.opening_balance) * 100 <= 25 THEN 'Low Utilization (≤25%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 25.01 AND 50 THEN 'Moderate Utilization (25-50%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 50.01 AND 75 THEN 'High Utilization (50-75%)'
          WHEN (l.balance / al.opening_balance) * 100 BETWEEN 75.01 AND 90 THEN 'Very High Utilization (75-90%)'
          WHEN (l.balance / al.opening_balance) * 100 > 90 THEN 'Critical Utilization (>90%)'
          ELSE 'Unknown'
        END AS loan_utilization_category,

        CASE
          WHEN al.opening_balance = 0 THEN 'No Data'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 <= 10 THEN 'Minimal Paydown (≤10%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 10.01 AND 25 THEN 'Low Paydown (10-25%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 25.01 AND 50 THEN 'Moderate Paydown (25-50%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 BETWEEN 50.01 AND 75 THEN 'Good Paydown (50-75%)'
          WHEN ((al.opening_balance - l.balance) / al.opening_balance) * 100 > 75 THEN 'Excellent Paydown (>75%)'
          ELSE 'Unknown'
        END AS loan_paydown_category,

        CASE
          WHEN l.balance = 0 OR al.payment_periodic = 0 THEN 'No Data'
          WHEN (al.payment_periodic / l.balance) * 100 < 1 THEN 'Very Low Capacity (<1%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 1 AND 2 THEN 'Low Capacity (1-2%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 2.01 AND 4 THEN 'Moderate Capacity (2-4%)'
          WHEN (al.payment_periodic / l.balance) * 100 BETWEEN 4.01 AND 8 THEN 'Good Capacity (4-8%)'
          WHEN (al.payment_periodic / l.balance) * 100 > 8 THEN 'Excellent Capacity (>8%)'
          ELSE 'Unknown'
        END AS payment_capacity_category,

        CASE
          WHEN al.number_of_payments = 0 THEN 'No Term Data'
          WHEN (date_diff('month', a.date_opened, l.record_date) / al.number_of_payments) * 100 <= 25 THEN 'Early Stage (≤25%)'
          WHEN (date_diff('month', a.date_opened, l.record_date) / al.number_of_payments) * 100 BETWEEN 25.01 AND 50 THEN 'Mid-Early Stage (25-50%)'
          WHEN (date_diff('month', a.date_opened, l.record_date) / al.number_of_payments) * 100 BETWEEN 50.01 AND 75 THEN 'Mid-Late Stage (50-75%)'
          WHEN (date_diff('month', a.date_opened, l.record_date) / al.number_of_payments) * 100 > 75 THEN 'Final Stage (>75%)'
          ELSE 'Unknown'
        END AS loan_lifecycle_stage,

        CASE
          WHEN al.opening_balance = 0 OR l.balance = 0 OR al.payment_periodic = 0 THEN 'Insufficient Data'
          WHEN (l.balance / al.opening_balance) * 100 > 90 AND (al.payment_periodic / l.balance) * 100 < 2 THEN 'High Risk'
          WHEN (l.balance / al.opening_balance) * 100 > 75 AND (al.payment_periodic / l.balance) * 100 < 3 THEN 'Elevated Risk'
          WHEN (l.balance / al.opening_balance) * 100 < 50 AND (al.payment_periodic / l.balance) * 100 > 4 THEN 'Low Risk'
          ELSE 'Moderate Risk'
        END AS combined_risk_category,

        al.loan_purpose_code_id,
        al.loan_officer_userid,
        m.branch_number,

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

        CASE
          WHEN m.branch_number = 1 THEN 'Large Branch (20K+ members)'
          WHEN m.branch_number IN (0, 4, 5) THEN 'Medium Branch (5K-15K members)'
          WHEN m.branch_number IN (2, 3) THEN 'Small Branch (1K-5K members)'
          WHEN m.branch_number = 6 THEN 'Specialty Branch (<100 members)'
          ELSE 'Other Size'
        END AS branch_size_category,

        -- Demographics
        CASE WHEN e.dob IS NULL THEN NULL ELSE date_diff('year', e.dob, l.record_date) END AS member_age_years,

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
        END AS member_age_category,

        CASE
          WHEN e.gender = 'M' THEN 'Male'
          WHEN e.gender = 'F' THEN 'Female'
          WHEN e.gender = 'O' THEN 'Other'
          WHEN e.gender = '' OR e.gender IS NULL THEN 'Unknown'
          ELSE 'Other'
        END AS member_gender,

        e.city AS member_city,
        e.state AS member_state,
        substr(e.zip, 1, 5) AS member_zip5,

        CASE
          WHEN e.state = 'CO' THEN 'Colorado Resident'
          WHEN e.state IN ('TX','AZ','CA','NM','FL','KS','WA','MO','OK') THEN 'Major Out-of-State'
          WHEN e.state IS NOT NULL AND e.state <> '' AND e.state <> 'CO' THEN 'Other Out-of-State'
          ELSE 'Unknown State'
        END AS member_state_category,

        e.occupation AS member_occupation,
        e.naics_occupation_code,

        CASE
          WHEN upper(coalesce(e.occupation, '')) LIKE '%RETIRED%' OR upper(coalesce(e.occupation, '')) LIKE '%RETIREMENT%' THEN 'Retired'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%STUDENT%' OR upper(coalesce(e.occupation, '')) LIKE '%SCHOOL%' THEN 'Student'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%TEACHER%' OR upper(coalesce(e.occupation, '')) LIKE '%EDUCATION%' OR upper(coalesce(e.occupation, '')) LIKE '%PROFESSOR%' THEN 'Education'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%NURSE%' OR upper(coalesce(e.occupation, '')) LIKE '%DOCTOR%' OR upper(coalesce(e.occupation, '')) LIKE '%MEDICAL%' OR upper(coalesce(e.occupation, '')) LIKE '%HEALTHCARE%' THEN 'Healthcare'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%ENGINEER%' OR upper(coalesce(e.occupation, '')) LIKE '%TECHNICIAN%' OR upper(coalesce(e.occupation, '')) LIKE '%IT %' OR upper(coalesce(e.occupation, '')) LIKE '%COMPUTER%' THEN 'Engineering/Tech'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%MANAGER%' OR upper(coalesce(e.occupation, '')) LIKE '%DIRECTOR%' OR upper(coalesce(e.occupation, '')) LIKE '%EXECUTIVE%' THEN 'Management'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%SALES%' OR upper(coalesce(e.occupation, '')) LIKE '%MARKETING%' THEN 'Sales/Marketing'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%GOVERNMENT%' OR upper(coalesce(e.occupation, '')) LIKE '%FEDERAL%' OR upper(coalesce(e.occupation, '')) LIKE '%STATE %' THEN 'Government'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%UNEMPLOYED%' OR upper(coalesce(e.occupation, '')) LIKE '%NOT EMPLOYED%' THEN 'Unemployed'
          WHEN upper(coalesce(e.occupation, '')) LIKE '%HOMEMAKER%' OR upper(coalesce(e.occupation, '')) LIKE '%HOUSEWIFE%' THEN 'Homemaker'
          WHEN coalesce(e.occupation, '') = '' THEN 'Unknown Occupation'
          ELSE 'Other Occupation'
        END AS member_occupation_category,

        CASE WHEN m.join_date IS NULL THEN NULL ELSE date_diff('year', m.join_date, l.record_date) END AS member_tenure_years,

        CASE
          WHEN m.join_date IS NULL THEN 'Unknown Tenure'
          WHEN date_diff('year', m.join_date, l.record_date) < 1 THEN 'New Member (<1 year)'
          WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 1 AND 2 THEN 'Recent Member (1-2 years)'
          WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 3 AND 5 THEN 'Established Member (3-5 years)'
          WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 6 AND 10 THEN 'Long-term Member (6-10 years)'
          WHEN date_diff('year', m.join_date, l.record_date) BETWEEN 11 AND 20 THEN 'Veteran Member (11-20 years)'
          WHEN date_diff('year', m.join_date, l.record_date) > 20 THEN 'Legacy Member (20+ years)'
          ELSE 'Unknown Tenure'
        END AS member_tenure_category,

        m.collection_queue_id,
        m.delinquency_status_code_id,
        m.date_first_delinquent,

        CASE WHEN m.date_first_delinquent IS NOT NULL THEN 'Has Delinquency History' ELSE 'No Known Delinquency History' END AS member_delinquency_history,

        m.number_of_accounts AS member_total_accounts,

        CASE
          WHEN m.number_of_accounts <= 1 THEN 'Single Product (1 account)'
          WHEN m.number_of_accounts BETWEEN 2 AND 3 THEN 'Multi-Product (2-3 accounts)'
          WHEN m.number_of_accounts BETWEEN 4 AND 6 THEN 'High Engagement (4-6 accounts)'
          WHEN m.number_of_accounts > 6 THEN 'Very High Engagement (7+ accounts)'
          ELSE 'Unknown Engagement'
        END AS member_engagement_level,

        -- delinquency basic
        CASE WHEN date_diff('day', l.next_payment_date, l.record_date) < 0 THEN 0
             ELSE date_diff('day', l.next_payment_date, l.record_date) END AS days_delinquent,

        CASE
          WHEN al.last_payment_date IS NULL AND l.next_payment_date IS NOT NULL AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 'First Payment Delinquency'
          WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 1 AND 30  THEN '1-30 days'
          WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 31 AND 60 THEN '31-60 days'
          WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 61 AND 90 THEN '61-90 days'
          WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 91 AND 120 THEN '91-120 days'
          WHEN date_diff('day', l.next_payment_date, l.record_date) > 120 THEN 'Over 120 days'
          ELSE '0 days'
        END AS Delinquency_Bracket,

        t.credit_card,
        upper(coalesce(t.description, '')) AS desc_u,
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
        END AS loan_main_category,

        pn.phone_number AS member_phone,
        e.email1 AS member_email
    FROM "AwsDataCatalog"."silver_know"."eom_loan" l
    CROSS JOIN date_params dp
    JOIN "AwsDataCatalog"."silver_know"."account" a
      ON a.account_id = l.account_id
    JOIN "AwsDataCatalog"."silver_know"."account_loan" al
      ON a.account_id = al.account_id
     AND a.credit_union = al.credit_union
    JOIN "AwsDataCatalog"."silver_know"."account_types" t
      ON t.account_type = l.account_type
     AND t.credit_union = a.credit_union
    JOIN "AwsDataCatalog"."silver_know"."member" m
      ON a.member_number = m.member_number
     AND a.credit_union  = m.credit_union
    JOIN "AwsDataCatalog"."silver_know"."entity" e
      ON m.member_entity_id = e.entity_id
     AND m.credit_union     = e.credit_union
    LEFT JOIN "AwsDataCatalog"."silver_know"."phone_number" pn
      ON e.entity_id = pn.entity_id
     AND e.credit_union = pn.credit_union
     AND pn.primary_phone = 1
    WHERE l.record_date IN (dp.previous_month_end, dp.current_month_end)
      AND l.date_closed IS NULL
      AND l.balance > 0
      AND coalesce(a.current_balance, l.balance) > 0
      AND coalesce(t.credit_card, 'N') NOT IN ('Y','X','1')
),
member_portfolio AS (
    SELECT
        a.credit_union,
        a.member_number,
        COUNT(DISTINCT el.account_id) AS member_total_loans,
        SUM(el.balance) AS member_total_loan_balance,
        SUM(CASE WHEN date_diff('day', el.next_payment_date, el.record_date) > 0 THEN el.balance ELSE 0 END) AS member_total_delinquent_balance,
        MAX(date_diff('day', el.next_payment_date, el.record_date)) AS member_worst_delinquency_days,
        SUM(CASE WHEN date_diff('day', el.next_payment_date, el.record_date) > 0 THEN 1 ELSE 0 END) AS member_delinquent_loan_count,
        CASE
            WHEN SUM(el.balance) <= 10000 THEN 'Low Exposure (≤$10K)'
            WHEN SUM(el.balance) BETWEEN 10001 AND 50000 THEN 'Medium Exposure ($10K-$50K)'
            WHEN SUM(el.balance) BETWEEN 50001 AND 100000 THEN 'High Exposure ($50K-$100K)'
            WHEN SUM(el.balance) > 100000 THEN 'Very High Exposure (>$100K)'
            ELSE 'Unknown'
        END AS member_exposure_category,
        CASE
            WHEN COUNT(DISTINCT el.account_id) > 1
             AND SUM(CASE WHEN date_diff('day', el.next_payment_date, el.record_date) > 0 THEN 1 ELSE 0 END) > 1
            THEN 1 ELSE 0
        END AS has_multiple_delinquent_loans
    FROM "AwsDataCatalog"."silver_know"."eom_loan" el
    CROSS JOIN date_params dp
    JOIN "AwsDataCatalog"."silver_know"."account" a
      ON el.account_id = a.account_id
     AND el.credit_union = a.credit_union
    WHERE el.record_date = dp.current_month_end
      AND el.date_closed IS NULL
      AND el.balance > 0
    GROUP BY a.credit_union, a.member_number
),
collection_activity AS (
    SELECT
        ch.credit_union,
        ch.account_id,
        COUNT(*) AS collection_contacts_90d,
        COUNT(DISTINCT date(ch.created_timestamp)) AS collection_contact_days_90d,
        SUM(CASE WHEN ch.promise_to_pay = 1 THEN 1 ELSE 0 END) AS promises_made_90d,
        SUM(ch.promise_to_pay_amt) AS total_promise_amount_90d,
        SUM(ch.actual_amount_paid) AS total_collected_90d,
        max(ch.created_timestamp) AS last_collection_contact_date,
        date_diff('day', max(ch.created_timestamp), current_date) AS days_since_last_contact,
        -- última acción / usuario usando max_by
        max_by(coalesce(cca.description, 'UNSPECIFIED'), ch.created_timestamp) AS last_collection_action,
        max_by(ch.created_by_userid, ch.created_timestamp)                      AS last_collection_user,
        SUM(CASE
              WHEN ch.promise_to_pay = 1
               AND ch.promise_to_pay_date >= current_date
               AND ch.promise_to_pay_date <= date_add('day', 30, current_date)
              THEN ch.promise_to_pay_amt ELSE 0
            END) AS pending_promises_next_30d,
        CASE WHEN SUM(ch.promise_to_pay_amt) > 0
             THEN round((SUM(ch.actual_amount_paid) / SUM(ch.promise_to_pay_amt)) * 100, 2)
             ELSE NULL END AS collection_effectiveness_pct
    FROM "AwsDataCatalog"."silver_know"."collection_history" ch
    LEFT JOIN "AwsDataCatalog"."silver_know"."collection_custom_action" cca
      ON ch.collection_custom_action_id = cca.collection_custom_action_id
     AND ch.credit_union = cca.credit_union
    WHERE ch.created_timestamp >= date_add('day', -90, current_date)
    GROUP BY ch.credit_union, ch.account_id
),
current_collection_queue AS (
    SELECT
        ajcq.credit_union,
        ajcq.account_id,
        cq.description AS collection_queue_name,
        cq.days_delinquent_beg AS queue_min_days,
        cq.days_delinquent_end AS queue_max_days,
        ajcq.manually_added AS manually_added_to_queue,
        ajcq.keep_in_queue AS keep_in_current_queue,
        ajcq.created_timestamp AS date_added_to_queue,
        date_diff('day', ajcq.created_timestamp, current_date) AS days_in_current_queue
    FROM "AwsDataCatalog"."silver_know"."account_join_collection_queue" ajcq
    JOIN "AwsDataCatalog"."silver_know"."collection_queue" cq
      ON ajcq.collection_queue_id = cq.collection_queue_id
     AND ajcq.credit_union       = cq.credit_union
),
recovery_metrics AS (
    SELECT
        a.credit_union,
        a.account_id,
        1 AS is_charged_off,
        a.charge_off_date,
        date_diff('day', a.charge_off_date, current_date) AS days_since_chargeoff,
        co.original_principal AS chargeoff_original_principal,
        co.principal AS chargeoff_current_principal,
        co.recovered_principal,
        co.recovered_interest,
        co.recovered_fees,
        (co.recovered_principal + co.recovered_interest + co.recovered_fees) AS total_recovered,
        CASE WHEN co.original_principal > 0
             THEN round((co.recovered_principal / co.original_principal) * 100, 2)
             ELSE 0 END AS recovery_rate_pct,
        co.status AS chargeoff_status,
        co.bankruptcy AS bankruptcy_status,
        co.collection_agency_id AS external_agency_id,
        CASE
            WHEN co.collection_agency_id IS NOT NULL THEN 'Placed with Agency'
            WHEN co.bankruptcy IS NOT NULL AND co.bankruptcy <> '' THEN 'Bankruptcy'
            WHEN co.status = 'C' THEN 'Closed'
            WHEN co.status = 'A' THEN 'Active'
            ELSE 'Other'
        END AS recovery_status,
        co.last_payment_date AS chargeoff_last_payment_date
    FROM "AwsDataCatalog"."silver_know"."account" a
    LEFT JOIN "AwsDataCatalog"."silver_know"."charge_off" co
      ON a.account_id = co.account_id
     AND a.credit_union = co.credit_union
    WHERE a.charge_off_date IS NOT NULL
),
loan_deferment_status AS (
    SELECT
        ld.credit_union,
        ld.account_id,
        1 AS has_deferment,
        ld.start_date AS deferment_start_date,
        ld.end_deferment_date,
        ld.fully_processed AS deferment_fully_processed,
        ld.interest_accrued AS deferment_interest_accrued,
        ld.date_of_first_delinquency AS delinq_date_before_deferment,
        ld.account_status_prior_to_deferment,
        CASE
            WHEN ld.end_deferment_date IS NULL THEN 'Active (No End Date)'
            WHEN ld.end_deferment_date >= current_date THEN 'Active Deferment'
            WHEN ld.end_deferment_date < current_date
              AND ld.end_deferment_date >= date_add('month', -6, current_date) THEN 'Recently Completed (<6 months)'
            WHEN ld.end_deferment_date < date_add('month', -6, current_date) THEN 'Historical Deferment (>6 months ago)'
            ELSE 'Unknown'
        END AS deferment_status,
        CASE
            WHEN ld.end_deferment_date IS NULL THEN date_diff('day', ld.start_date, current_date)
            ELSE date_diff('day', ld.start_date, ld.end_deferment_date)
        END AS deferment_duration_days,
        ld.created_timestamp AS deferment_created_date,
        ld.created_by_userid AS deferment_created_by
    FROM "AwsDataCatalog"."silver_know"."loan_deferment" ld
    WHERE ld.start_date IS NOT NULL
),
payment_arrangements AS (
    SELECT
        lsp.credit_union,
        lsp.account_id,
        COUNT(*) AS total_skip_payments,
        SUM(lsp.number_of_extensions) AS total_extensions,
        max(lsp.payment_to_skip) AS last_skip_payment_date,
        SUM(lsp.fee_amount) AS total_skip_fees,
        SUM(CASE WHEN lsp.skip_completed = 1 THEN 1 ELSE 0 END) AS completed_skips,
        max(CASE WHEN lsp.skip_completed = 0 AND lsp.payment_to_skip >= current_date THEN 1 ELSE 0 END) AS has_active_skip_payment,
        max(CASE WHEN lsp.payment_to_skip >= date_add('month', -3, current_date) THEN lsp.payment_to_skip ELSE NULL END) AS recent_skip_payment_date,
        max(CASE WHEN lsp.payment_to_skip >= date_add('month', -3, current_date) THEN 1 ELSE 0 END) AS has_recent_skip_payment
    FROM "AwsDataCatalog"."silver_know"."loan_skip_payment" lsp
    WHERE lsp.payment_to_skip >= date_add('month', -12, current_date)
    GROUP BY lsp.credit_union, lsp.account_id
),
c1 AS (
    SELECT b.*
    FROM base b
    CROSS JOIN date_params dp
    WHERE b.record_date = dp.previous_month_end
),
c2 AS (
    SELECT
      l.credit_union,
      l.account_id,
      CASE WHEN date_diff('day', l.next_payment_date, l.record_date) < 0 THEN 0
           ELSE date_diff('day', l.next_payment_date, l.record_date) END AS days_delinquent_m2,
      CASE
        WHEN al.last_payment_date IS NULL
          AND l.next_payment_date IS NOT NULL
          AND date_diff('day', l.next_payment_date, l.record_date) >= 1 THEN 'First Payment Delinquency'
        WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 1 AND 30  THEN '1-30 days'
        WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 31 AND 60 THEN '31-60 days'
        WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 61 AND 90 THEN '61-90 days'
        WHEN date_diff('day', l.next_payment_date, l.record_date) BETWEEN 91 AND 120 THEN '91-120 days'
        WHEN date_diff('day', l.next_payment_date, l.record_date) > 120 THEN 'Over 120 days'
        ELSE '0 days'
      END AS Delinquency_Bracket_m2
    FROM "AwsDataCatalog"."silver_know"."eom_loan" l
    CROSS JOIN date_params dp
    JOIN "AwsDataCatalog"."silver_know"."account" a
      ON a.account_id = l.account_id
     AND a.credit_union = l.credit_union
    JOIN "AwsDataCatalog"."silver_know"."account_loan" al
      ON a.account_id = al.account_id
     AND a.credit_union = al.credit_union
    WHERE l.record_date = dp.current_month_end
      AND l.date_closed IS NULL
),
summary_m1 AS (
    SELECT
        COUNT(DISTINCT c1.account_id) AS total_loans_m1,
        SUM(c1.balance)               AS total_balance_m1,
        COUNT(DISTINCT CASE WHEN c1.days_delinquent > 0 THEN c1.account_id END) AS delinquent_loans_m1,
        SUM(CASE WHEN c1.days_delinquent > 0 THEN c1.balance ELSE 0 END)        AS delinquent_balance_m1,
        round( (COUNT(DISTINCT CASE WHEN c1.days_delinquent > 0 THEN c1.account_id END)
                / NULLIF(COUNT(DISTINCT c1.account_id),0)) * 100, 2) AS pct_loans_delq_m1,
        round( (SUM(CASE WHEN c1.days_delinquent > 0 THEN c1.balance ELSE 0 END)
                / NULLIF(SUM(c1.balance),0)) * 100, 2) AS pct_balance_delq_m1
    FROM c1
),
summary_m2 AS (
    SELECT
        COUNT(DISTINCT c2.account_id) AS total_loans_m2,
        SUM(l.balance)                AS total_balance_m2,
        COUNT(DISTINCT CASE WHEN c2.days_delinquent_m2 > 0 THEN c2.account_id END) AS delinquent_loans_m2,
        SUM(CASE WHEN c2.days_delinquent_m2 > 0 THEN l.balance ELSE 0 END)         AS delinquent_balance_m2,
        round( (COUNT(DISTINCT CASE WHEN c2.days_delinquent_m2 > 0 THEN c2.account_id END)
                / NULLIF(COUNT(DISTINCT c2.account_id),0)) * 100, 2) AS pct_loans_delq_m2,
        round( (SUM(CASE WHEN c2.days_delinquent_m2 > 0 THEN l.balance ELSE 0 END)
                / NULLIF(SUM(l.balance),0)) * 100, 2) AS pct_balance_delq_m2
    FROM c2
    CROSS JOIN date_params dp
    JOIN "AwsDataCatalog"."silver_know"."eom_loan" l
      ON c2.account_id = l.account_id
     AND c2.credit_union = l.credit_union
     AND l.record_date = dp.current_month_end
    JOIN "AwsDataCatalog"."silver_know"."account_types" t
      ON t.account_type = l.account_type
     AND t.credit_union = l.credit_union
    WHERE coalesce(t.credit_card,'N') NOT IN ('Y','X','1')
)
SELECT
    -- Clasificación FI
    c1.credit_union AS credit_union,
    fi.idfi         AS idFi,
    ci.credit_union_name AS CU_Name,

    -- Datos base y métricas
    c1.record_date,
    c1.record_ym,
    c1.member_number,
    c1.account_number,
    c1.account_id,
    c1.credit_score,
    coalesce(c1.credit_score_code, 'No Data') AS credit_score_code,
    c1.date_opened,

    c1.loan_age_months,
    c1.loan_age_category,

    c1.original_loan_term_months,
    c1.payments_per_year,
    c1.maturity_date,
    c1.loan_term_category,

    c1.original_loan_amount,
    c1.highest_balance_attained,
    c1.interest_rate,
    c1.scheduled_payment,
    c1.delinquent_amount,
    c1.last_payment_date,
    c1.interest_accumulated,
    c1.principal_and_interest,

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

    c1.loan_utilization_category,
    c1.loan_paydown_category,
    c1.payment_capacity_category,
    c1.loan_lifecycle_stage,
    c1.combined_risk_category,

    c1.loan_purpose_code_id,
    c1.loan_officer_userid,
    c1.branch_number,
    c1.branch_description,
    c1.branch_size_category,

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

    -- ranks (Athena)
    (coalesce(array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c1.Delinquency_Bracket), 0) - 1) AS rank_m1,
    (coalesce(array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c2.Delinquency_Bracket_m2), 0) - 1) AS rank_m2,

    CASE
      WHEN c2.Delinquency_Bracket_m2 IS NULL THEN 'Loan Paid Off'
      WHEN array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c2.Delinquency_Bracket_m2)
         > array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c1.Delinquency_Bracket)
        THEN 'Deteriorated'
      WHEN array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c2.Delinquency_Bracket_m2)
         = array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c1.Delinquency_Bracket)
        THEN 'No Change'
      ELSE 'Improved'
    END AS delinquency_change,

    CASE
      WHEN c2.Delinquency_Bracket_m2 IS NULL THEN 0
      WHEN array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c2.Delinquency_Bracket_m2)
         > array_position(ARRAY['0 days','First Payment Delinquency','1-30 days','31-60 days','61-90 days','91-120 days','Over 120 days'], c1.Delinquency_Bracket)
        THEN 1
      ELSE 0
    END AS deterioration_flag,

    coalesce(mp.member_total_loans, 1) AS member_total_loans,
    coalesce(mp.member_total_loan_balance, c1.balance) AS member_total_loan_balance,
    coalesce(mp.member_total_delinquent_balance, 0) AS member_total_delinquent_balance,
    coalesce(mp.member_worst_delinquency_days, c1.days_delinquent) AS member_worst_delinquency_days,
    coalesce(mp.member_delinquent_loan_count, 0) AS member_delinquent_loan_count,
    coalesce(mp.member_exposure_category, 'Unknown') AS member_exposure_category,
    coalesce(mp.has_multiple_delinquent_loans, 0) AS has_multiple_delinquent_loans,

    coalesce(ca.collection_contacts_90d, 0) AS collection_contacts_90d,
    coalesce(ca.collection_contact_days_90d, 0) AS collection_contact_days_90d,
    coalesce(ca.promises_made_90d, 0) AS promises_made_90d,
    coalesce(ca.total_promise_amount_90d, 0) AS total_promise_amount_90d,
    coalesce(ca.total_collected_90d, 0) AS total_collected_90d,
    ca.last_collection_contact_date,
    ca.days_since_last_contact,
    ca.last_collection_action,
    ca.last_collection_user,
    coalesce(ca.pending_promises_next_30d, 0) AS pending_promises_next_30d,
    ca.collection_effectiveness_pct,

    ccq.collection_queue_name,
    ccq.queue_min_days,
    ccq.queue_max_days,
    ccq.manually_added_to_queue,
    ccq.keep_in_current_queue,
    ccq.date_added_to_queue,
    ccq.days_in_current_queue,

    coalesce(rm.is_charged_off, 0) AS is_charged_off,
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

    coalesce(lds.has_deferment, 0) AS has_loan_deferment,
    lds.deferment_start_date,
    lds.end_deferment_date,
    lds.deferment_status,
    lds.deferment_duration_days,
    lds.deferment_interest_accrued,
    lds.delinq_date_before_deferment,
    lds.account_status_prior_to_deferment,
    lds.deferment_created_date,
    lds.deferment_created_by,

    coalesce(pa.total_skip_payments, 0) AS total_skip_payments,
    coalesce(pa.total_extensions, 0) AS total_extensions,
    pa.last_skip_payment_date,
    coalesce(pa.total_skip_fees, 0) AS total_skip_fees,
    coalesce(pa.completed_skips, 0) AS completed_skips,
    coalesce(pa.has_active_skip_payment, 0) AS has_active_skip_payment,
    pa.recent_skip_payment_date,
    coalesce(pa.has_recent_skip_payment, 0) AS has_recent_skip_payment,

    CASE
        WHEN lds.deferment_status IN ('Active Deferment', 'Active (No End Date)') THEN 'DEFERRED (Active)'
        WHEN pa.has_active_skip_payment = 1 THEN 'SKIP PAYMENT (Active)'
        WHEN pa.has_recent_skip_payment = 1 THEN 'SKIP PAYMENT (Recent - Last 3 months)'
        WHEN lds.deferment_status = 'Recently Completed (<6 months)' THEN 'DEFERRED (Recently Completed)'
        WHEN lds.has_deferment = 1 OR pa.total_skip_payments > 0 THEN 'Has Deferment/Skip History'
        ELSE 'No Deferment/Skip'
    END AS deferment_skip_consolidated_status,

    CASE
        WHEN lds.deferment_status IN ('Active Deferment', 'Active (No End Date)')
          OR coalesce(pa.has_active_skip_payment,0) = 1
          OR coalesce(pa.has_recent_skip_payment,0) = 1
        THEN 1 ELSE 0
    END AS has_any_active_deferment,

    sm1.total_loans_m1,
    sm1.total_balance_m1,
    sm1.delinquent_loans_m1,
    sm1.delinquent_balance_m1,
    sm1.pct_loans_delq_m1,

    sm2.total_loans_m2,
    sm2.total_balance_m2,
    sm2.delinquent_loans_m2,
    sm2.delinquent_balance_m2,
    sm2.pct_loans_delq_m2,

    (sm2.delinquent_balance_m2 - sm1.delinquent_balance_m1) AS change_delinquent_balance,
    (sm2.delinquent_loans_m2 - sm1.delinquent_loans_m1)     AS change_delinquent_loans,
    (sm2.total_balance_m2 - sm1.total_balance_m1)             AS change_total_balance,
    (sm2.total_loans_m2 - sm1.total_loans_m1)                 AS change_total_loans,

    round(((sm2.delinquent_balance_m2 - sm1.delinquent_balance_m1) / NULLIF(sm1.delinquent_balance_m1, 0)) * 100, 2) AS pct_change_delinquent_balance,
    round(((sm2.delinquent_loans_m2 - sm1.delinquent_loans_m1) / NULLIF(sm1.delinquent_loans_m1, 0)) * 100, 2)       AS pct_change_delinquent_loans

FROM c1
CROSS JOIN summary_m1 sm1
CROSS JOIN summary_m2 sm2
LEFT JOIN c2
  ON c1.account_id   = c2.account_id
 AND c1.credit_union = c2.credit_union
LEFT JOIN member_portfolio mp
  ON c1.member_number = mp.member_number
 AND c1.credit_union  = mp.credit_union
LEFT JOIN collection_activity ca
  ON c1.account_id   = ca.account_id
 AND c1.credit_union = ca.credit_union
LEFT JOIN current_collection_queue ccq
  ON c1.account_id   = ccq.account_id
 AND c1.credit_union = ccq.credit_union
LEFT JOIN recovery_metrics rm
  ON c1.account_id   = rm.account_id
 AND c1.credit_union = rm.credit_union
LEFT JOIN loan_deferment_status lds
  ON c1.account_id   = lds.account_id
 AND c1.credit_union = lds.credit_union
LEFT JOIN payment_arrangements pa
  ON c1.account_id   = pa.account_id
 AND c1.credit_union = pa.credit_union

-- JOINS DE CLASIFICACIÓN FI
LEFT JOIN "AwsDataCatalog"."silver_know"."blossomcompany_olb_map" fi
  ON lower(trim(fi.prodigy_code)) = lower(trim(c1.credit_union))
LEFT JOIN "AwsDataCatalog"."silver_know"."credit_union_info" ci
  ON ci.credit_union   = c1.credit_union
 AND ci.flag_inactive <> 'Y'

ORDER BY c1.account_id;
