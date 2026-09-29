"""
Load the clean CSVs into a local SQLite database (data/kestrel_sales.db) and run every
file in sql/. Each '-- @query: name' block is exported to analysis/sql_outputs/<file>__<name>.csv.
SQLite was chosen so the project reproduces with zero setup; the SQL is standard (CTEs, window
functions) and ports to PostgreSQL / SQL Server with minor date-function changes.
Run:  python src/run_sql.py
"""
import re, sqlite3, pandas as pd
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
db = ROOT / "data" / "kestrel_sales.db"; db.unlink(missing_ok=True)
con = sqlite3.connect(db)
for t in ["leads", "opportunities", "customers", "reps", "products", "quotas"]:
    pd.read_csv(ROOT / "data" / "clean" / f"{t}.csv").to_sql(t, con, index=False)
con.execute("CREATE INDEX ix_opp_lead ON opportunities(lead_id)")
con.execute("CREATE INDEX ix_opp_rep ON opportunities(rep_id, close_month)")
out = ROOT / "analysis" / "sql_outputs"; out.mkdir(parents=True, exist_ok=True)
for f in sorted((ROOT / "sql").glob("*.sql")):
    blocks = re.split(r"^-- @query:\s*(\w+)\s*$", f.read_text(), flags=re.M)
    for name, sql in zip(blocks[1::2], blocks[2::2]):
        df = pd.read_sql_query(sql.strip().rstrip(";"), con)
        df.to_csv(out / f"{f.stem}__{name}.csv", index=False)
        print(f"{f.stem}__{name}: {len(df)} rows")
con.close()
