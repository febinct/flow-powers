---
name: duckdb-analysis
description: |
  Analyze tabular data files (CSV / TSV / Parquet / JSON / Excel) with SQL via a
  bundled DuckDB tool — no database setup, no loading data into the conversation.
  Use when the user wants to explore, aggregate, join, filter, profile, slice,
  pivot, crosstab, rank, dedupe, or summarize a data file with SQL, or asks
  "query this data", "run SQL on this CSV/Parquet", "read this Excel/CSV",
  "what's in this file", "load this file", "aggregate/group by", "join these
  files", "top N", "count distinct", "distribution of", "compare across",
  "summary stats", "how many rows", "analyze this dataset in DuckDB". Runs SQL
  in-process and prints only the result; raw rows never enter the context window.
---

# DuckDB Analysis

Query tabular files with SQL through a self-contained DuckDB tool. The point is
**leverage + hygiene**: DuckDB reads CSV/TSV/Parquet/JSON/Excel directly (no
import step, no schema), and only the *derived answer* — an aggregate, a
profile, a filtered slice — is printed. The raw dataset stays in DuckDB, out of
the conversation.

**Announce at start:** "Using the data-analysis skill (DuckDB over SQL)."

## The tool

`scripts/duckdb_tool.py` — a `uv` script with inline deps (duckdb, pyarrow); no
install step, `uv` fetches them on first run. It maps files to table names and
runs SQL over them.

```bash
# One or more files → table names, then SQL:
uv run scripts/duckdb_tool.py \
  --load sales=/data/sales.csv --load ref=/data/regions.parquet \
  --sql "SELECT r.name, sum(s.revenue) rev
         FROM sales s JOIN ref r ON s.region_id = r.id
         GROUP BY 1 ORDER BY rev DESC LIMIT 20"

# A .sql file, result written out instead of printed:
uv run scripts/duckdb_tool.py --load t=in.parquet --sql-file q.sql --out out.parquet
```

Flags: `--load TABLE=PATH` (repeatable), `--sql` OR `--sql-file`, `--out
file.parquet|.csv` (write instead of print), `--database file.db` (default
in-memory). Loaders auto-detect by extension: `.csv/.tsv`, `.parquet/.pq`,
`.json/.ndjson`, `.xlsx/.xls`. Table/column identifiers are whitelisted and
paths are parameterised — safe against SQL injection.

## How to work

1. **Profile before analyzing.** Don't guess the schema. First run a cheap
   shape query so you know columns, types, and size:
   ```sql
   SELECT * FROM t LIMIT 5;                          -- shape + sample
   DESCRIBE t;                                        -- columns + types
   SELECT count(*) FROM t;                            -- row count
   ```
2. **Push the work into SQL — never into the conversation.** Aggregate, filter,
   join, window, and summarize *in the query*. Return the small result, not the
   rows. Do NOT `cat` the file or `SELECT *` a large table into the transcript —
   that's the exact context bloat this skill exists to avoid.
3. **Answer with the result.** Read the printed table and state the finding.
   When the output would itself be large (hundreds of rows), `--out` it to a
   Parquet/CSV and report the path + a summary, not the dump.
4. **`--database file.db`** for a multi-step investigation you'll return to
   (tables persist across runs); in-memory (default) for one-shots.

## When context-mode is available

If the `ctx_*` tools are present, prefer running the tool through
`ctx_execute`/`ctx_batch_execute` — the query output is indexed in the sandbox
and only what you surface reaches the conversation. This skill and context-mode
are the same discipline (keep raw data out of the window) at two layers; use
both when you can.

## Guardrails
- **Never load raw rows into the conversation** to "look at the data" — query
  for the shape instead. That defeats the whole purpose.
- **Read the file, don't assume its schema** — profile first (step 1).
- **Excel with `all_varchar`** — `.xlsx` loads every column as text (safe
  default); `CAST` in SQL when you need numeric/date math.
- The tool only *reads* data files and writes explicit `--out` results; it never
  mutates the source files.
