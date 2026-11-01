# Project 2 — Healthcare RCM Intelligence

## Project overview
An end-to-end portfolio analysis of a **synthetic US healthcare revenue-cycle dataset**. The project examines claim denials, eligibility and authorization patterns, payer/provider performance, payment turnaround, financial reconciliation, submission rework, claim events, and follow-up operations.

## Business questions
### Denial intelligence
- How do denial rates and denied amounts vary by payer and provider?
- How are eligibility coverage and authorization outcomes associated with claim denials?
- Which denial reasons, service codes, and provider/payer combinations warrant review?

### Financial performance
- What are billed, allowed, paid, adjustment, and outstanding AR amounts?
- How long does it take to receive the first payment after claim submission?
- Do claim-level payment and adjustment amounts reconcile with transaction tables?
- Which payers carry the largest 120+ day AR exposure?

### Operations and follow-up
- What are the most common submission rejection reasons and retry patterns?
- How do submission attempts relate to claim denials?
- How many open/in-progress follow-up actions were overdue at the historical cutoff?
- What do claim events reveal about payment/denial processing and event completeness?
- Which claims should be reviewed against payer filing-limit thresholds?

## Repository structure
- `data/` — 16 synthetic CSV tables.
- `excel/` — Excel profiling, data-quality, relationship, and business-rule workbooks.
- `python/` — Python/MySQL data-quality validation script and instructions.
- `sql/` — executable MySQL analysis scripts for denial, financial, and operations analysis.
- `documentation/` — SQL business-analysis evidence and data-file inventory.
- `evidence/` — reserved for verified query-result screenshots/exports and Power BI screenshots.
- `powerbi/` — reserved for the final `.pbix` report file.

## Power BI report
The report contains five pages:
1. Executive Overview
2. Denial Intelligence
3. Financial & AR
4. Operations & Follow-up
5. Business Insights & Recommendations

The `.pbix` file is not included in this repository package yet; add the final saved report to `powerbi/` before publishing if you want the interactive report available with the repository.

## Tools and techniques
MySQL, Python (pandas), Excel, Power BI, DAX, CTEs, joins, aggregate analysis, `COUNT(DISTINCT ...)`, conditional aggregation, `CAST`, `STR_TO_DATE`, `DATEDIFF`, `COALESCE`, and financial reconciliation.

## Key metric definitions and interpretation
- Claim-level counts use distinct `Claim_ID` where appropriate.
- First-payment turnaround is measured from `Claim_Submission_Date` to the earliest recorded `Payment_Date` for each claim. First payment does not necessarily mean final claim resolution.
- Outstanding AR in the dashboard is calculated as total billed amount minus total paid amount; interpret it as a gross outstanding balance under this project definition.
- AR aging and overdue follow-up analysis use a fixed historical reference date of **2020-12-31**. These are historical snapshot measures, not current operational balances or currently overdue actions.
- The overdue follow-up count uses distinct `Action_ID` values, limited to `Open` and `In Progress` actions with `Next_Followup_Date` before 2020-12-31. Validated result: **2,864 In Progress + 2,008 Open = 4,872**.
- Service-line status groups can overlap at claim level. An open action does not by itself prove that the related denial remains unresolved.
- Filing-limit output is an age-based screening flag against the fixed reference date, not proof of a contractual filing-limit violation.
- All data is synthetic and does not represent real patient, payer, provider, or insurer performance.

## How to run
1. Create the MySQL schema `healthcare_rcm_v8`.
2. Load the CSV files from `data/` into tables using their corresponding table names.
3. Run the SQL scripts in `sql/` against the schema.
4. Run the Python validation script using the instructions in `python/README.md`.
5. Open the Excel workbooks in `excel/` to review profiling and validation outputs.
6. Add the final `.pbix` file to `powerbi/` and verified screenshots/exports to `evidence/` before publishing those artifacts.

## Portfolio integrity
This is a synthetic-data portfolio project. Present findings as results from this dataset only; do not imply they represent real-world payer/provider performance or real patient records.
