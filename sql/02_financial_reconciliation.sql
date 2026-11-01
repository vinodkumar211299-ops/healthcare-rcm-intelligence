-- Project 2: Healthcare RCM Intelligence
-- Category 2: Financial Reconciliation
-- Database: healthcare_rcm_v8

USE healthcare_rcm_v8;

-- Q6A. How many payment records and unique claims with payments exist?
SELECT COUNT(*) AS Total_Payment_Records,
       COUNT(DISTINCT Claim_ID) AS Unique_Claims_With_Payments,
       COUNT(*) - COUNT(DISTINCT Claim_ID) AS Additional_Payment_Records
FROM fact_payments;

-- Q6B. What are the submission and payment date ranges?
SELECT COUNT(*) AS Matched_Records,
       MIN(c.Claim_Submission_Date) AS Earliest_Submission,
       MAX(c.Claim_Submission_Date) AS Latest_Submission,
       MIN(p.Payment_Date) AS Earliest_Payment,
       MAX(p.Payment_Date) AS Latest_Payment
FROM fact_claims c
INNER JOIN fact_payments p ON c.Claim_ID = p.Claim_ID;

-- Q6C. What is the average time to first payment by payer?
WITH first_payment AS (
    SELECT Claim_ID, MIN(STR_TO_DATE(Payment_Date, '%Y-%m-%d')) AS First_Payment_Date
    FROM fact_payments
    GROUP BY Claim_ID
),
claim_turnaround AS (
    SELECT c.Claim_ID, c.Payer_ID,
           DATEDIFF(fp.First_Payment_Date, STR_TO_DATE(c.Claim_Submission_Date, '%Y-%m-%d')) AS Days_To_First_Payment
    FROM fact_claims c
    INNER JOIN first_payment fp ON c.Claim_ID = fp.Claim_ID
)
SELECT p.Payer_Name, COUNT(*) AS Claims_With_Payments,
       ROUND(AVG(ct.Days_To_First_Payment), 2) AS Avg_Days_To_First_Payment,
       MIN(ct.Days_To_First_Payment) AS Min_Days,
       MAX(ct.Days_To_First_Payment) AS Max_Days
FROM claim_turnaround ct
INNER JOIN dim_payer p ON ct.Payer_ID = p.Payer_ID
GROUP BY p.Payer_Name
ORDER BY Avg_Days_To_First_Payment DESC;

-- Q7A. Do claim-level payment totals reconcile with the payment transaction table?
WITH payment_summary AS (
    SELECT Claim_ID, SUM(CAST(Payment_Amount AS DECIMAL(18,2))) AS Transaction_Payments
    FROM fact_payments
    GROUP BY Claim_ID
)
SELECT COUNT(*) AS Matched_Claims,
       ROUND(SUM(CAST(c.Paid_Amount AS DECIMAL(18,2))), 2) AS Claim_Level_Paid,
       ROUND(SUM(COALESCE(p.Transaction_Payments, 0)), 2) AS Payment_Table_Total,
       ROUND(SUM(CAST(c.Paid_Amount AS DECIMAL(18,2))) - SUM(COALESCE(p.Transaction_Payments, 0)), 2) AS Payment_Reconciliation_Gap
FROM fact_claims c
LEFT JOIN payment_summary p ON c.Claim_ID = p.Claim_ID;

-- Q7B. Do claim-level adjustment totals reconcile with the adjustment transaction table?
WITH adjustment_summary AS (
    SELECT Claim_ID, SUM(CAST(Adjustment_Amount AS DECIMAL(18,2))) AS Transaction_Adjustments
    FROM fact_adjustments
    GROUP BY Claim_ID
)
SELECT COUNT(*) AS Total_Claims,
       ROUND(SUM(CAST(c.Adjustment_Amount AS DECIMAL(18,2))), 2) AS Claim_Level_Adjustments,
       ROUND(SUM(COALESCE(a.Transaction_Adjustments, 0)), 2) AS Adjustment_Table_Total,
       ROUND(SUM(CAST(c.Adjustment_Amount AS DECIMAL(18,2))) - SUM(COALESCE(a.Transaction_Adjustments, 0)), 2) AS Adjustment_Reconciliation_Gap
FROM fact_claims c
LEFT JOIN adjustment_summary a ON c.Claim_ID = a.Claim_ID;
