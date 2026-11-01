-- Project 2: Healthcare RCM Intelligence
-- Category 3: Operations and Follow-up
-- Database: healthcare_rcm_v8

USE healthcare_rcm_v8;

-- Q8A. Which rejection reasons are most common and have repeat attempts?
SELECT Rejection_Reason,
       COUNT(*) AS Rejected_Submissions,
       COUNT(DISTINCT Claim_ID) AS Unique_Claims,
       COUNT(DISTINCT CASE WHEN Attempt_Number > 1 THEN Claim_ID END) AS Claims_With_Repeat_Attempts
FROM fact_claim_submissions
WHERE Clearinghouse_Status = 'Rejected'
GROUP BY Rejection_Reason
ORDER BY Rejected_Submissions DESC;

-- Q8B. How do submission outcomes vary by attempt number?
SELECT Attempt_Number, Clearinghouse_Status,
       COUNT(*) AS Total_Submissions,
       COUNT(DISTINCT Claim_ID) AS Unique_Claims
FROM fact_claim_submissions
GROUP BY Attempt_Number, Clearinghouse_Status
ORDER BY Attempt_Number, Clearinghouse_Status;

-- Q9. Are claims with multiple submission attempts more likely to have denials?
WITH submission_summary AS (
    SELECT Claim_ID, MAX(CAST(Attempt_Number AS UNSIGNED)) AS Max_Attempts
    FROM fact_claim_submissions
    GROUP BY Claim_ID
),
denial_claims AS (SELECT DISTINCT Claim_ID FROM fact_denials)
SELECT CASE WHEN s.Max_Attempts = 1 THEN 'First Attempt Only' ELSE 'Multiple Attempts' END AS Submission_Group,
       COUNT(DISTINCT s.Claim_ID) AS Total_Claims,
       COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
       ROUND(COUNT(DISTINCT d.Claim_ID) * 100.0 / NULLIF(COUNT(DISTINCT s.Claim_ID), 0), 2) AS Denial_Rate_Pct
FROM submission_summary s
LEFT JOIN denial_claims d ON s.Claim_ID = d.Claim_ID
GROUP BY Submission_Group
ORDER BY Denial_Rate_Pct DESC;

-- Q10A. How many denials have open or in-progress actions and what is the associated denied amount?
WITH open_denials AS (
    SELECT DISTINCT d.Denial_ID, CAST(d.Denied_Amount AS DECIMAL(18,2)) AS Denied_Amount
    FROM fact_denials d
    INNER JOIN fact_claim_actions a ON d.Denial_ID = a.Denial_ID
    WHERE a.Action_Status IN ('Open', 'In Progress')
)
SELECT COUNT(*) AS Unique_Denials, ROUND(SUM(Denied_Amount), 2) AS Denied_Amount
FROM open_denials;

-- Q10B. How many open/in-progress follow-up actions were overdue
-- as of the fixed historical snapshot date 2020-12-31?
-- The fixed cutoff keeps this result aligned with the Power BI dashboard.
SELECT Action_Status,
       COUNT(DISTINCT Action_ID) AS Overdue_Actions
FROM fact_claim_actions
WHERE Action_Status IN ('Open', 'In Progress')
  AND Next_Followup_Date IS NOT NULL
  AND STR_TO_DATE(Next_Followup_Date, '%Y-%m-%d') < '2020-12-31'
GROUP BY Action_Status
ORDER BY Action_Status;

-- Q11A. What event types and date ranges are recorded?
SELECT Event_Type, COUNT(*) AS Total_Events,
       COUNT(DISTINCT Claim_ID) AS Unique_Claims,
       MIN(STR_TO_DATE(Event_Date, '%Y-%m-%d')) AS Earliest_Event,
       MAX(STR_TO_DATE(Event_Date, '%Y-%m-%d')) AS Latest_Event
FROM fact_claim_events
GROUP BY Event_Type
ORDER BY Total_Events DESC;

-- Q11B. What is the time from submission to the recorded payment or denial event?
WITH event_dates AS (
    SELECT Claim_ID,
        MIN(CASE WHEN Event_Type = 'Submitted' THEN STR_TO_DATE(Event_Date, '%Y-%m-%d') END) AS Submitted_Date,
        MIN(CASE WHEN Event_Type = 'Payment Posted' THEN STR_TO_DATE(Event_Date, '%Y-%m-%d') END) AS Payment_Date,
        MIN(CASE WHEN Event_Type = 'Denied' THEN STR_TO_DATE(Event_Date, '%Y-%m-%d') END) AS Denial_Date
    FROM fact_claim_events
    GROUP BY Claim_ID
)
SELECT CASE
           WHEN Payment_Date IS NOT NULL THEN 'Payment Posted'
           WHEN Denial_Date IS NOT NULL THEN 'Denied'
           ELSE 'No Payment or Denial Event'
       END AS Claim_Outcome,
       COUNT(*) AS Total_Claims,
       ROUND(AVG(CASE
           WHEN Payment_Date IS NOT NULL THEN DATEDIFF(Payment_Date, Submitted_Date)
           WHEN Denial_Date IS NOT NULL THEN DATEDIFF(Denial_Date, Submitted_Date)
       END), 2) AS Avg_Days_From_Submission,
       MIN(CASE
           WHEN Payment_Date IS NOT NULL THEN DATEDIFF(Payment_Date, Submitted_Date)
           WHEN Denial_Date IS NOT NULL THEN DATEDIFF(Denial_Date, Submitted_Date)
       END) AS Min_Days,
       MAX(CASE
           WHEN Payment_Date IS NOT NULL THEN DATEDIFF(Payment_Date, Submitted_Date)
           WHEN Denial_Date IS NOT NULL THEN DATEDIFF(Denial_Date, Submitted_Date)
       END) AS Max_Days
FROM event_dates
GROUP BY Claim_Outcome
ORDER BY Avg_Days_From_Submission DESC;

-- Q11C. How many claims have payment events, denial events, both, or neither?
WITH claim_events AS (
    SELECT Claim_ID,
        MAX(CASE WHEN Event_Type = 'Submitted' THEN 1 ELSE 0 END) AS Has_Submitted,
        MAX(CASE WHEN Event_Type = 'Payment Posted' THEN 1 ELSE 0 END) AS Has_Payment,
        MAX(CASE WHEN Event_Type = 'Denied' THEN 1 ELSE 0 END) AS Has_Denial
    FROM fact_claim_events
    GROUP BY Claim_ID
)
SELECT CASE
           WHEN Has_Payment = 1 AND Has_Denial = 1 THEN 'Both Payment and Denial'
           WHEN Has_Payment = 1 THEN 'Payment Only'
           WHEN Has_Denial = 1 THEN 'Denial Only'
           ELSE 'Neither Payment nor Denial'
       END AS Event_Classification,
       COUNT(*) AS Total_Claims
FROM claim_events
GROUP BY Event_Classification
ORDER BY Total_Claims DESC;

-- Q11D. What are the statuses of claims with neither payment nor denial events?
SELECT c.Claim_Status, COUNT(*) AS Total_Claims
FROM fact_claims c
LEFT JOIN (
    SELECT DISTINCT Claim_ID FROM fact_claim_events
    WHERE Event_Type IN ('Payment Posted', 'Denied')
) e ON c.Claim_ID = e.Claim_ID
WHERE e.Claim_ID IS NULL
GROUP BY c.Claim_Status
ORDER BY Total_Claims DESC;

-- Q12. Which claims exceed payer filing-limit thresholds and need review?
-- Note: the fixed reference date 2020-12-31 is a screening assumption, not proof of violation.
SELECT p.Payer_Name, p.Claim_Filing_Limit_Days,
       COUNT(*) AS Total_Claims,
       SUM(CASE
           WHEN DATEDIFF('2020-12-31', STR_TO_DATE(c.Claim_Submission_Date, '%Y-%m-%d'))
                > CAST(p.Claim_Filing_Limit_Days AS UNSIGNED)
           THEN 1 ELSE 0
       END) AS Claims_Over_Filing_Limit
FROM fact_claims c
INNER JOIN dim_payer p ON c.Payer_ID = p.Payer_ID
GROUP BY p.Payer_Name, p.Claim_Filing_Limit_Days
ORDER BY Claims_Over_Filing_Limit DESC;
