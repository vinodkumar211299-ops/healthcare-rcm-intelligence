"""
Project 2 — Healthcare RCM Intelligence
Python Data Quality & Business Rule Validation

Purpose
-------
Connect to the MySQL database healthcare_rcm_v8, profile every table, validate
candidate primary/foreign keys, review financial/date/status fields, and export
the results to an Excel workbook.

Requirements
------------
pip install pandas mysql-connector-python openpyxl

Run
---
python project2_data_quality_validation.py

Notes
-----
- The source dataset is synthetic.
- This script does not alter database tables.
- Update connection settings if your MySQL setup differs.
- Enter the MySQL password when prompted; it is not stored in this file.
"""

from getpass import getpass
from pathlib import Path
import sys
import pandas as pd
import mysql.connector
from mysql.connector import Error


DATABASE = "healthcare_rcm_v8"
OUTPUT_FILE = Path("Project2_v8_Python_Data_Quality.xlsx")

# Edit these if your local MySQL connection uses different settings.
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "database": DATABASE,
}

PRIMARY_KEYS = {
    "dim_patient": "Patient_ID",
    "dim_encounter": "Encounter_ID",
    "dim_provider": "Provider_ID",
    "dim_payer": "Payer_ID",
    "dim_policy": "Policy_ID",
    "fact_claims": "Claim_ID",
    "fact_service_lines": "Service_Line_ID",
    "fact_eligibility": "Eligibility_ID",
    "fact_authorization": "Authorization_ID",
    "fact_denials": "Denial_ID",
    "fact_payments": "Payment_ID",
    "fact_adjustments": "Adjustment_ID",
    "fact_claim_submissions": "Submission_ID",
    "fact_claim_events": "Status_Event_ID",
    "fact_claim_actions": "Action_ID",
}

# Candidate relationships for this project. These are validation checks,
# not enforced database constraints.
RELATIONSHIPS = [
    ("dim_encounter", "Patient_ID", "dim_patient", "Patient_ID"),
    ("fact_claims", "Patient_ID", "dim_patient", "Patient_ID"),
    ("fact_claims", "Encounter_ID", "dim_encounter", "Encounter_ID"),
    ("fact_claims", "Provider_ID", "dim_provider", "Provider_ID"),
    ("fact_claims", "Payer_ID", "dim_payer", "Payer_ID"),
    ("fact_service_lines", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_eligibility", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_authorization", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_denials", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_payments", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_adjustments", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_claim_submissions", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_claim_events", "Claim_ID", "fact_claims", "Claim_ID"),
    ("fact_claim_actions", "Claim_ID", "fact_claims", "Claim_ID"),
    ("bridge_policy_service_benefit", "Policy_ID", "dim_policy", "Policy_ID"),
]

FINANCIAL_NAME_HINTS = (
    "amount", "billed", "allowed", "paid", "payment", "adjustment",
    "copay", "coinsurance", "deductible", "charge", "units"
)
DATE_NAME_HINT = "date"
STATUS_NAME_HINTS = ("status", "flag", "type", "category", "reason", "code")


def connect_to_database():
    """Connect to MySQL without hard-coding the password."""
    password = getpass(f"MySQL password for {DB_CONFIG['user']}@{DB_CONFIG['host']}: ")
    config = dict(DB_CONFIG)
    config["password"] = password
    return mysql.connector.connect(**config)


def quote_identifier(identifier):
    """Safely quote a MySQL table/column identifier."""
    return "`" + identifier.replace("`", "``") + "`"


def load_all_tables(conn):
    """Load table names and DataFrames from the selected schema."""
    cursor = conn.cursor()
    cursor.execute("SHOW TABLES")
    tables = [row[0] for row in cursor.fetchall()]
    cursor.close()

    table_data = {}
    for table in tables:
        print(f"Loading table: {table}")
        query = f"SELECT * FROM {quote_identifier(table)}"
        table_data[table] = pd.read_sql(query, conn)
    return table_data


def profile_tables(table_data):
    table_rows, missing_rows, column_rows = [], [], []

    for table, df in table_data.items():
        table_rows.append({
            "Table": table,
            "Total_Rows": len(df),
            "Total_Columns": len(df.columns),
            "Duplicate_Rows": int(df.duplicated().sum()),
        })

        for col in df.columns:
            missing_count = int(df[col].isna().sum())
            missing_rows.append({
                "Table": table,
                "Column": col,
                "Missing_Count": missing_count,
                "Missing_Percent": round(
                    (missing_count / len(df) * 100) if len(df) else 0, 2
                ),
            })
            column_rows.append({
                "Table": table,
                "Column": col,
                "Data_Type": str(df[col].dtype),
                "Unique_Values": int(df[col].nunique(dropna=True)),
                "Missing_Count": missing_count,
            })

    return (
        pd.DataFrame(table_rows),
        pd.DataFrame(missing_rows),
        pd.DataFrame(column_rows),
    )


def validate_primary_keys(table_data):
    results = []
    for table, key in PRIMARY_KEYS.items():
        if table not in table_data:
            results.append({
                "Table": table, "Primary_Key": key,
                "Check_Status": "Table not found",
                "Missing_IDs": None, "Duplicate_IDs": None,
            })
            continue

        df = table_data[table]
        if key not in df.columns:
            results.append({
                "Table": table, "Primary_Key": key,
                "Check_Status": "Column not found",
                "Missing_IDs": None, "Duplicate_IDs": None,
            })
            continue

        results.append({
            "Table": table,
            "Primary_Key": key,
            "Check_Status": "Checked",
            "Missing_IDs": int(df[key].isna().sum()),
            "Duplicate_IDs": int(df[key].duplicated(keep=False).sum()),
        })
    return pd.DataFrame(results)


def validate_relationships(table_data):
    results = []
    for child_table, child_col, parent_table, parent_col in RELATIONSHIPS:
        result = {
            "Child_Table": child_table,
            "Child_Column": child_col,
            "Parent_Table": parent_table,
            "Parent_Column": parent_col,
            "Check_Status": "Checked",
            "Child_Nonnull_Values": None,
            "Unmatched_Rows": None,
            "Unmatched_Percent": None,
        }

        if child_table not in table_data or parent_table not in table_data:
            result["Check_Status"] = "Table not found"
            results.append(result)
            continue

        child_df, parent_df = table_data[child_table], table_data[parent_table]
        if child_col not in child_df.columns or parent_col not in parent_df.columns:
            result["Check_Status"] = "Column not found"
            results.append(result)
            continue

        # Compare normalized string forms because source columns may be TEXT
        # and may contain mixed numeric/string representations.
        child = child_df[child_col]
        parent_values = set(parent_df[parent_col].dropna().astype(str).str.strip())
        child_nonnull = child.notna()
        child_normalized = child.astype("string").str.strip()
        unmatched_mask = child_nonnull & ~child_normalized.isin(parent_values)
        unmatched = int(unmatched_mask.sum())
        nonnull_count = int(child_nonnull.sum())

        result.update({
            "Child_Nonnull_Values": nonnull_count,
            "Unmatched_Rows": unmatched,
            "Unmatched_Percent": round(
                (unmatched / nonnull_count * 100) if nonnull_count else 0, 2
            ),
        })
        results.append(result)
    return pd.DataFrame(results)


def validate_financial_fields(table_data):
    results = []
    for table, df in table_data.items():
        for col in df.columns:
            if not any(hint in col.lower() for hint in FINANCIAL_NAME_HINTS):
                continue

            numeric = pd.to_numeric(df[col], errors="coerce")
            invalid_nonempty = int((df[col].notna() & numeric.isna()).sum())
            results.append({
                "Table": table,
                "Column": col,
                "Nonempty_Values": int(df[col].notna().sum()),
                "Invalid_Numeric_Values": invalid_nonempty,
                "Missing_Values": int(df[col].isna().sum()),
                "Negative_Values": int((numeric < 0).sum()),
            })
    return pd.DataFrame(results)


def validate_date_fields(table_data):
    results = []
    for table, df in table_data.items():
        for col in df.columns:
            if DATE_NAME_HINT not in col.lower():
                continue
            parsed = pd.to_datetime(df[col], errors="coerce")
            results.append({
                "Table": table,
                "Column": col,
                "Total_Rows": len(df),
                "Missing_Dates": int(df[col].isna().sum()),
                "Invalid_Nonempty_Dates": int(
                    (df[col].notna() & parsed.isna()).sum()
                ),
                "Earliest_Valid_Date": parsed.min(),
                "Latest_Valid_Date": parsed.max(),
            })
    return pd.DataFrame(results)


def profile_status_and_flags(table_data):
    results = []
    for table, df in table_data.items():
        for col in df.columns:
            if not any(hint in col.lower() for hint in STATUS_NAME_HINTS):
                continue
            values = df[col].dropna().astype(str).unique().tolist()
            results.append({
                "Table": table,
                "Column": col,
                "Distinct_Values": int(df[col].nunique(dropna=True)),
                "Values_Found_Sample": ", ".join(values[:30]),
            })
    return pd.DataFrame(results)


def validate_claim_business_rules(table_data):
    """Run claim-level checks when the expected columns exist."""
    results = []
    claims = table_data.get("fact_claims")

    if claims is None:
        return pd.DataFrame([{
            "Validation_Check": "fact_claims available",
            "Issue_Count": None,
            "Notes": "fact_claims table not found",
        }])

    def add_check(name, count, notes=""):
        results.append({
            "Validation_Check": name,
            "Issue_Count": int(count) if count is not None else None,
            "Notes": notes,
        })

    # Financial fields: convert only for validation; original table remains unchanged.
    required_financial = ["Billed_Amount", "Allowed_Amount", "Paid_Amount"]
    missing_columns = [c for c in required_financial if c not in claims.columns]
    if missing_columns:
        add_check("Claim financial rules", None, "Missing columns: " + ", ".join(missing_columns))
    else:
        billed = pd.to_numeric(claims["Billed_Amount"], errors="coerce")
        allowed = pd.to_numeric(claims["Allowed_Amount"], errors="coerce")
        paid = pd.to_numeric(claims["Paid_Amount"], errors="coerce")
        add_check("Invalid billed amount (non-numeric)", (claims["Billed_Amount"].notna() & billed.isna()).sum())
        add_check("Negative billed amount", (billed < 0).sum())
        add_check("Allowed amount greater than billed amount", ((allowed > billed) & billed.notna() & allowed.notna()).sum())
        add_check("Paid amount greater than allowed amount", ((paid > allowed) & paid.notna() & allowed.notna()).sum())

    # Claim ID length and duplicate checks.
    if "Claim_ID" in claims.columns:
        claim_ids = claims["Claim_ID"].dropna().astype(str).str.strip()
        add_check("Claim IDs not 14 characters", (claim_ids.str.len() != 14).sum())
        add_check("Duplicate Claim IDs (rows after first)", claims["Claim_ID"].duplicated().sum())
    else:
        add_check("Claim ID checks", None, "Claim_ID column not found")

    # Service date logic.
    date_cols = ["Service_Start_Date", "Service_End_Date"]
    if all(c in claims.columns for c in date_cols):
        start = pd.to_datetime(claims["Service_Start_Date"], errors="coerce")
        end = pd.to_datetime(claims["Service_End_Date"], errors="coerce")
        add_check("Missing or invalid service start dates", start.isna().sum())
        add_check("Missing or invalid service end dates", end.isna().sum())
        add_check("Service end date before start date", ((end < start) & end.notna() & start.notna()).sum())
    else:
        add_check("Service date checks", None, "One or both service date columns not found")

    # Status frequency table is also exported separately.
    if "Claim_Status" in claims.columns:
        status_counts = claims["Claim_Status"].value_counts(dropna=False)
    else:
        status_counts = pd.Series(dtype="int64")

    return pd.DataFrame(results), status_counts.rename_axis("Claim_Status").reset_index(name="Count")


def write_workbook(sheets, output_file):
    """Write all profiling results into a single Excel workbook."""
    with pd.ExcelWriter(output_file, engine="openpyxl") as writer:
        for sheet_name, df in sheets.items():
            if df is None:
                continue
            if not isinstance(df, pd.DataFrame):
                df = pd.DataFrame(df)
            # Excel worksheet names are limited to 31 characters.
            safe_name = sheet_name[:31]
            if df.empty:
                df = pd.DataFrame({"Note": ["No rows generated for this check."]})
            df.to_excel(writer, sheet_name=safe_name, index=False)

        # Apply practical formatting to each sheet.
        for ws in writer.book.worksheets:
            ws.freeze_panes = "A2"
            ws.auto_filter.ref = ws.dimensions
            for column_cells in ws.columns:
                max_len = max(
                    (len(str(cell.value)) for cell in list(column_cells)[:200] if cell.value is not None),
                    default=10,
                )
                ws.column_dimensions[column_cells[0].column_letter].width = min(max(max_len + 2, 12), 42)


def main():
    conn = None
    try:
        conn = connect_to_database()
        print(f"\nConnected successfully to database: {DATABASE}")

        table_data = load_all_tables(conn)
        if not table_data:
            print("No tables found. Check the selected database.")
            return 1

        table_summary, missing_values, column_profile = profile_tables(table_data)
        primary_key_checks = validate_primary_keys(table_data)
        foreign_key_checks = validate_relationships(table_data)
        financial_field_checks = validate_financial_fields(table_data)
        date_field_checks = validate_date_fields(table_data)
        status_flag_review = profile_status_and_flags(table_data)
        business_rule_checks, claim_status_counts = validate_claim_business_rules(table_data)

        sheets = {
            "Table_Summary": table_summary,
            "Missing_Values": missing_values,
            "Column_Profile": column_profile,
            "Primary_Key_Check": primary_key_checks,
            "Foreign_Key_Check": foreign_key_checks,
            "Financial_Field_Checks": financial_field_checks,
            "Date_Field_Checks": date_field_checks,
            "Status_Flag_Review": status_flag_review,
            "Business_Rule_Checks": business_rule_checks,
            "Claim_Status_Counts": claim_status_counts,
        }
        write_workbook(sheets, OUTPUT_FILE)

        print("\n========== TABLE SUMMARY ==========")
        print(table_summary.to_string(index=False))
        print("\n========== PRIMARY KEY CHECKS ==========")
        print(primary_key_checks.to_string(index=False))
        print("\n========== FOREIGN KEY CHECKS ==========")
        print(foreign_key_checks.to_string(index=False))
        print("\n========== CLAIM BUSINESS RULE CHECKS ==========")
        print(business_rule_checks.to_string(index=False))
        print(f"\nCompleted. Results saved to: {OUTPUT_FILE.resolve()}")
        return 0

    except Error as exc:
        print(f"MySQL error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"Unexpected error: {exc}", file=sys.stderr)
        raise
    finally:
        if conn is not None and conn.is_connected():
            conn.close()
            print("Database connection closed.")


if __name__ == "__main__":
    raise SystemExit(main())
