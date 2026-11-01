-- Project 2: Healthcare RCM Intelligence
-- Category 1: Denial Analysis
-- Database: healthcare_rcm_v8
-- Dataset is synthetic. Validate all reported findings against actual query outputs.

USE healthcare_rcm_v8;

-- Q1. Which payers have the highest claim denial rates and denied amounts?
WITH claim_summary AS (
    SELECT Payer_ID, COUNT(DISTINCT Claim_ID) AS Total_Claims
    FROM fact_claims
    GROUP BY Payer_ID
),
denial_summary AS (
    SELECT
        c.Payer_ID,
        COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
        SUM(CAST(d.Denied_Amount AS DECIMAL(18,2))) AS Total_Denied_Amount
    FROM fact_claims c
    INNER JOIN fact_denials d ON c.Claim_ID = d.Claim_ID
    GROUP BY c.Payer_ID
)
SELECT
    p.Payer_Name,
    cs.Total_Claims,
    COALESCE(ds.Denied_Claims, 0) AS Denied_Claims,
    ROUND(COALESCE(ds.Denied_Claims, 0) * 100.0 / NULLIF(cs.Total_Claims, 0), 2) AS Denial_Rate_Pct,
    ROUND(COALESCE(ds.Total_Denied_Amount, 0), 2) AS Total_Denied_Amount
FROM claim_summary cs
LEFT JOIN denial_summary ds ON cs.Payer_ID = ds.Payer_ID
LEFT JOIN dim_payer p ON cs.Payer_ID = p.Payer_ID
ORDER BY Denial_Rate_Pct DESC;

-- Q2. Which providers have the highest claim denial rates and denied amounts?
WITH claim_summary AS (
    SELECT Provider_ID, COUNT(DISTINCT Claim_ID) AS Total_Claims
    FROM fact_claims
    GROUP BY Provider_ID
),
denial_summary AS (
    SELECT
        c.Provider_ID,
        COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
        SUM(CAST(d.Denied_Amount AS DECIMAL(18,2))) AS Total_Denied_Amount
    FROM fact_claims c
    INNER JOIN fact_denials d ON c.Claim_ID = d.Claim_ID
    GROUP BY c.Provider_ID
)
SELECT
    p.Provider_ID, p.Provider_Name, p.Specialty, cs.Total_Claims,
    COALESCE(ds.Denied_Claims, 0) AS Denied_Claims,
    ROUND(COALESCE(ds.Denied_Claims, 0) * 100.0 / NULLIF(cs.Total_Claims, 0), 2) AS Denial_Rate_Pct,
    ROUND(COALESCE(ds.Total_Denied_Amount, 0), 2) AS Total_Denied_Amount
FROM claim_summary cs
LEFT JOIN denial_summary ds ON cs.Provider_ID = ds.Provider_ID
LEFT JOIN dim_provider p ON cs.Provider_ID = p.Provider_ID
ORDER BY Denial_Rate_Pct DESC
LIMIT 10;

-- Q3. How do denial rates vary by eligibility coverage status?
WITH denial_claims AS (SELECT DISTINCT Claim_ID FROM fact_denials),
eligibility_summary AS (
    SELECT e.Coverage_Status,
           COUNT(DISTINCT c.Claim_ID) AS Total_Claims,
           COUNT(DISTINCT d.Claim_ID) AS Denied_Claims
    FROM fact_claims c
    INNER JOIN fact_eligibility e ON c.Claim_ID = e.Claim_ID
    LEFT JOIN denial_claims d ON c.Claim_ID = d.Claim_ID
    GROUP BY e.Coverage_Status
)
SELECT Coverage_Status, Total_Claims, Denied_Claims,
       ROUND(Denied_Claims * 100.0 / NULLIF(Total_Claims, 0), 2) AS Denial_Rate_Pct
FROM eligibility_summary
ORDER BY Denial_Rate_Pct DESC;

-- Q3 supporting. Is coverage valid on the service date?
SELECT e.Coverage_Valid_On_Service_Date,
       COUNT(DISTINCT c.Claim_ID) AS Total_Claims,
       COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
       ROUND(COUNT(DISTINCT d.Claim_ID) * 100.0 / NULLIF(COUNT(DISTINCT c.Claim_ID), 0), 2) AS Denial_Rate_Pct
FROM fact_claims c
INNER JOIN fact_eligibility e ON c.Claim_ID = e.Claim_ID
LEFT JOIN fact_denials d ON c.Claim_ID = d.Claim_ID
GROUP BY e.Coverage_Valid_On_Service_Date
ORDER BY Denial_Rate_Pct DESC;

-- Q4. Are authorization outcomes associated with claim denials?
WITH denial_claims AS (SELECT DISTINCT Claim_ID FROM fact_denials)
SELECT a.Authorization_Status,
       COUNT(DISTINCT c.Claim_ID) AS Total_Claims,
       COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
       ROUND(COUNT(DISTINCT d.Claim_ID) * 100.0 / NULLIF(COUNT(DISTINCT c.Claim_ID), 0), 2) AS Claim_Denial_Rate_Pct
FROM fact_claims c
INNER JOIN fact_authorization a ON c.Claim_ID = a.Claim_ID
LEFT JOIN denial_claims d ON c.Claim_ID = d.Claim_ID
GROUP BY a.Authorization_Status
ORDER BY Claim_Denial_Rate_Pct DESC;

-- Q4 supporting. What denial reasons occur when authorization is Not Required?
SELECT d.Denial_Category, d.Denial_Reason_Code,
       COUNT(*) AS Denial_Records,
       ROUND(SUM(CAST(d.Denied_Amount AS DECIMAL(18,2))), 2) AS Total_Denied_Amount
FROM fact_claims c
INNER JOIN fact_authorization a ON c.Claim_ID = a.Claim_ID
INNER JOIN fact_denials d ON c.Claim_ID = d.Claim_ID
WHERE a.Authorization_Status = 'Not Required'
GROUP BY d.Denial_Category, d.Denial_Reason_Code
ORDER BY Denial_Records DESC;

-- Q5A. Profile service lines by coding and documentation status.
SELECT Coding_Validation_Status, Documentation_Status,
       COUNT(*) AS Total_Service_Lines,
       SUM(CAST(Service_Line_Billed_Amount AS DECIMAL(18,2))) AS Total_Billed_Amount
FROM fact_service_lines
GROUP BY Coding_Validation_Status, Documentation_Status
ORDER BY Total_Service_Lines DESC;

-- Q5B. Claim denial rates by coding and documentation status.
WITH claim_denial AS (SELECT DISTINCT Claim_ID FROM fact_denials),
service_status AS (
    SELECT Claim_ID, Coding_Validation_Status, Documentation_Status
    FROM fact_service_lines
    GROUP BY Claim_ID, Coding_Validation_Status, Documentation_Status
)
SELECT s.Coding_Validation_Status, s.Documentation_Status,
       COUNT(DISTINCT s.Claim_ID) AS Total_Claims,
       COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
       ROUND(COUNT(DISTINCT d.Claim_ID) * 100.0 / NULLIF(COUNT(DISTINCT s.Claim_ID), 0), 2) AS Claim_Denial_Rate_Pct
FROM service_status s
LEFT JOIN claim_denial d ON s.Claim_ID = d.Claim_ID
GROUP BY s.Coding_Validation_Status, s.Documentation_Status
ORDER BY Claim_Denial_Rate_Pct DESC;

-- Q5C. How does benefit coverage relate to claim denial rates?
WITH claim_denial AS (SELECT DISTINCT Claim_ID FROM fact_denials),
claim_coverage AS (
    SELECT Claim_ID, Benefit_Covered_Flag
    FROM fact_service_lines
    GROUP BY Claim_ID, Benefit_Covered_Flag
)
SELECT s.Benefit_Covered_Flag,
       COUNT(DISTINCT s.Claim_ID) AS Total_Claims,
       COUNT(DISTINCT d.Claim_ID) AS Denied_Claims,
       ROUND(COUNT(DISTINCT d.Claim_ID) * 100.0 / NULLIF(COUNT(DISTINCT s.Claim_ID), 0), 2) AS Claim_Denial_Rate_Pct
FROM claim_coverage s
LEFT JOIN claim_denial d ON s.Claim_ID = d.Claim_ID
GROUP BY s.Benefit_Covered_Flag
ORDER BY Claim_Denial_Rate_Pct DESC;
