#!/usr/bin/env bash
# Rebuild everything from scratch (deterministic: fixed random seed).
set -euo pipefail
cd "$(dirname "$0")"
python src/generate_synthetic_data.py
python src/clean_data.py
python src/run_sql.py
python src/analysis.py
python src/build_excel_dashboard.py
python src/export_tableau.py
echo "Done. Open dashboard/Kestrel_Sales_Performance_Dashboard.xlsx in Excel to calculate the formulas."
