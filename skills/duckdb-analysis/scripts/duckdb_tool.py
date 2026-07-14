#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "duckdb>=1.0",
#   "pyarrow>=15",
# ]
# ///
"""
Generic DuckDB query/load tool.

A thin, reusable wrapper around an in-memory (or file-backed) DuckDB
connection. It is *not* tied to any analysis: it loads tabular files
(CSV/TSV/Parquet/JSON/Excel) into DuckDB tables and runs SQL over them.

It is the staging/query substrate for the Extract -> Transform -> View
pipeline (see docs/adr/0004): the View stage reads a transform's Parquet
output through this, and ad-hoc exploration uses it directly.

The identifier-safety helpers and the multi-format loader pattern are lifted
from the document-matching engine's match.py (clear-finance-skills); the
recon-specific join cascade is intentionally not carried over.

CLI:
    # Run SQL over one or more files mapped to table names:
    uv run duckdb_tool.py \
        --load wt=/data/floating_walls/weekly_transactions.parquet \
        --sql "SELECT sku_id, sum(total_qty) q FROM wt GROUP BY 1 ORDER BY q DESC LIMIT 20"

    # Or a .sql file, with results written to Parquet/CSV:
    uv run duckdb_tool.py --load t=in.parquet --sql-file q.sql --out out.parquet
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import duckdb

_IDENT_RX = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def safe_ident(name: str) -> str:
    """Whitelist a table/column identifier (letters, digits, underscore).

    Used for any identifier that flows into a SQL string-builder, so a
    table name can never inject SQL.
    """
    if not _IDENT_RX.match(name):
        raise ValueError(
            f"invalid identifier (use letters / digits / underscores only): {name!r}"
        )
    return name


def quote_col(name: str) -> str:
    """Double-quote a column identifier for SQL (handles spaces / mixed case)."""
    return '"' + name.replace('"', '""') + '"'


def loader_sql(path: Path) -> tuple[str, list]:
    """Return (sql, params) that reads `path` based on its extension.

    Parameterised so the path is never string-formatted into SQL.
    """
    ext = path.suffix.lower()
    p = str(path)
    if ext in {".csv", ".tsv"}:
        return ("SELECT * FROM read_csv_auto(?, header=true, sample_size=-1)", [p])
    if ext in {".parquet", ".pq"}:
        return ("SELECT * FROM read_parquet(?)", [p])
    if ext in {".json", ".ndjson"}:
        return ("SELECT * FROM read_json_auto(?)", [p])
    if ext in {".xlsx", ".xls"}:
        return ("SELECT * FROM read_xlsx(?, all_varchar=true)", [p])
    raise ValueError(f"unsupported file extension: {ext}")


def connect(database: str = ":memory:") -> duckdb.DuckDBPyConnection:
    """Open a DuckDB connection and best-effort load the excel extension."""
    conn = duckdb.connect(database)
    try:
        conn.execute("INSTALL excel; LOAD excel;")
    except Exception:
        pass
    return conn


def load_table(conn: duckdb.DuckDBPyConnection, table: str, path: Path) -> int:
    """Create `table` in `conn` from `path`; return the row count."""
    sql, params = loader_sql(path)
    conn.execute(f"CREATE OR REPLACE TABLE {safe_ident(table)} AS {sql}", params)
    return conn.execute(f"SELECT COUNT(*) FROM {safe_ident(table)}").fetchone()[0]


def write_out(conn: duckdb.DuckDBPyConnection, select_sql: str, out: Path) -> None:
    """Write the result of `select_sql` to `out` (Parquet or CSV by extension)."""
    ext = out.suffix.lower()
    if ext in {".parquet", ".pq"}:
        fmt = "(FORMAT PARQUET)"
    elif ext in {".csv"}:
        fmt = "(FORMAT CSV, HEADER)"
    else:
        raise ValueError(f"unsupported output extension: {ext}")
    out.parent.mkdir(parents=True, exist_ok=True)
    conn.execute(f"COPY ({select_sql}) TO ? {fmt}", [str(out)])


def _parse_load(spec: str) -> tuple[str, Path]:
    if "=" not in spec:
        raise ValueError(f"--load expects table=path, got: {spec!r}")
    table, path = spec.split("=", 1)
    return safe_ident(table.strip()), Path(path.strip())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Load files into DuckDB and run SQL.")
    ap.add_argument(
        "--load",
        action="append",
        default=[],
        metavar="TABLE=PATH",
        help="map a table name to a file (repeatable)",
    )
    ap.add_argument("--sql", help="SQL string to run")
    ap.add_argument("--sql-file", type=Path, help="path to a .sql file to run")
    ap.add_argument("--out", type=Path, help="write result to this Parquet/CSV file")
    ap.add_argument("--database", default=":memory:", help="DuckDB file (default in-memory)")
    args = ap.parse_args(argv)

    if not args.sql and not args.sql_file:
        ap.error("one of --sql or --sql-file is required")
    sql = args.sql or args.sql_file.read_text()

    conn = connect(args.database)
    try:
        for spec in args.load:
            table, path = _parse_load(spec)
            n = load_table(conn, table, path)
            print(f"loaded: {table}={n} rows", file=sys.stderr)

        if args.out:
            write_out(conn, sql, args.out)
            print(f"wrote: {args.out}", file=sys.stderr)
        else:
            rel = conn.sql(sql)
            print(rel)
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
