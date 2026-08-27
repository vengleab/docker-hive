# Tasks — Feature 003 (workload parity)

**Gate:** requires a working cluster from feature 001 (T019 complete). Runs on both
architectures once feature 002 lands.

---

## Phase P0 — Establish the baseline

> **No predecessor cluster is required, and none is assumed to exist.** This package is built
> to be lifted into a new, empty project (constitution P9). Everything these tasks need is in
> `reference/predecessor/`.

### T-P01 — Define the deterministic parity input and expected output
**FR:** FR-P02 · **Deps:** none
**Do:** The baseline is **computed, not captured.** Write `tests/fixtures/films.csv` — a small,
fixed, committed CSV — and `tests/fixtures/expected/wordcount.txt`, its word-count result
sorted by key. Because the input is committed and the transformation is pure, the expected
output is fully determined: derive it by hand or with a local script, and commit both.
**Why not capture it from a running predecessor:** its notebook reads
`hdfs://namenode:9000/data/films`, and that dataset is **not in its repository** — the
`.gitignore` there is the single line `data`. A baseline nobody can reproduce is not a
baseline. See `reference/predecessor/notebook-workload.md`.
**Done:** both files committed; the expected output is checkable by inspection; this task needs
no running cluster of any kind.

### T-P02 — [P] Build the fixtures
**FR:** FR-P02, FR-P05 · **Deps:** none
**Do:** Copy from `reference/predecessor/` into `tests/fixtures/`, keeping attribution headers:
- `spark_yarn_pi.py`, `submit_yarn.sh` — verbatim, then retarget endpoints and `SCRIPT_PATH`
  (it points at the predecessor's `/home/jovyan/work/`).
- `mapreduce_wordcount.py` — **write** this from the specification in
  `reference/predecessor/notebook-workload.md` § "The replacement fixture". Headless, reads the
  T-P01 input from HDFS. **Sort before comparing** — `reduceByKey` ordering is not guaranteed
  and an unsorted comparison is a flaky test waiting to happen.
- `WordCount.jar` — **write the source and build it.** The predecessor commits a prebuilt jar;
  a committed binary is not reproducible (constitution P3).
**Done:** every fixture runs against a cluster built solely from this package;
`grep -rn "docker-hive" tests/` finds nothing outside attribution comments (P9); the jar builds
from committed source.

---

## Phase P1 — Core equivalence

### T-P03 — [P] HDFS parity
**FR:** FR-P01 · **Deps:** T-P02, feature 001 T019
**Do:** Write a ≥100 MB file, read it back, verify the checksum. Assert the block count matches
the configured block size and that replication matches `dfs.replication`.
**Done:** checksum matches; block count and replication assertions pass; the test fails
correctly when a DataNode is stopped.

### T-P04 — MapReduce parity
**FR:** FR-P02 · **Deps:** T-P01, T-P03
**Do:** Load `tests/fixtures/films.csv` into HDFS and run the WordCount fixture on YARN.
Compare output **byte for byte** against `tests/fixtures/expected/wordcount.txt`, sorted.
**Done:** job reaches `SUCCEEDED`; output matches the committed expectation exactly. Any
difference is a provisioning defect to investigate — the transformation is pure and the input
is fixed, so there is no legitimate source of variation.

### T-P05 — [P] Hive parity, including ACID
**FR:** FR-P03 · **Deps:** feature 001 T019
**Do:** Via Beeline against HiveServer2: `CREATE DATABASE`, `CREATE TABLE`, `INSERT`, `SELECT`,
`JOIN`, `DROP`; a partitioned table with partition pruning; a transactional table with
`UPDATE` and `DELETE`, then confirm compaction runs. *(`docker-hive` enables `DbTxnManager`,
`hive.compactor.initiator.on`, and two compactor worker threads — ACID is in scope.)*
**Done:** every statement succeeds; the ACID table shows correct post-update state and
compaction completes.

### T-P06 — Hive-on-Tez behavioural equivalence
**FR:** FR-P04 · **Deps:** T-P05
**Do:** Run the same query set on Tez that `docker-hive` runs on MapReduce, and compare
results. Document any behavioural difference found.
**Done:** results match; the execution-engine change is documented in the migration guide
(FR-P11). This is the difference most likely to surface later as a confusing student bug, so it
is written down whether or not it causes a failure here.

### T-P07 — [P] Spark on YARN
**FR:** FR-P05 · **Deps:** T-P02, feature 001 T019
**Do:** Run the ported Pi job with `--master yarn --deploy-mode client`.
**Done:** job reaches `SUCCEEDED`; the result is within tolerance of π; the YARN application
appears in the ResourceManager UI.

### T-P08 — Spark–Hive integration
**FR:** FR-P06 · **Deps:** T-P05, T-P07
**Do:** Both directions: create a table in Beeline and read it from a `SparkSession` with
`enableHiveSupport()`; then create a table from Spark and read it in Beeline.
**Done:** both directions work. This is `docker-hive`'s "Spark over Hive" flow and its most
fragile integration — a failure here is a genuine blocker, not a nice-to-have.

### T-P09 — [P] Compression and native libraries
**FR:** FR-P07 · **Deps:** T-P04
**Do:** `hadoop checknative -a` and assert Snappy is available. Run a MapReduce job with Snappy
map-output compression and verify correct results.
**Done:** Snappy reported available; the compressed job succeeds with correct output.
**Why this matters:** `docker-hive` sets `io.compression.codecs` to SnappyCodec and enables map
output compression. A missing native codec can silently fall back — which looks like success
and is not. On ARM64 this check is shared with feature 002's T-A08.

---

## Phase P2 — Configuration parity

### T-P10 — Assert carried-over tuning
**FR:** FR-P08 · **Deps:** feature 001 T014, T019
**Do:** For every value in `docs/config-migration.md`'s "carried over" column, read the
cluster's **effective** configuration from Ambari's API and assert the value. Reading the
blueprint is not sufficient — the question is what the cluster actually runs.
**Done:** every carried-over value asserted; a deliberately altered value makes the test fail.

### T-P11 — [P] Assert dropped settings
**FR:** FR-P09 · **Deps:** T-P10
**Do:** Assert each deliberately dropped setting is absent or overridden. Specifically:
`dfs.permissions.enabled` is **not** `false`; `hadoop.http.staticuser.user` is not `root`;
services run as per-service users, not root; the database does not use `trust` authentication.
**Done:** all assertions pass, confirming the departures from `docker-hive` actually took
effect rather than being silently reintroduced by a stack default.

---

## Phase P3 — Documentation and execution

### T-P12 — Migration guide
**FR:** FR-P10, FR-P11, FR-P12 · **Deps:** T-P03…T-P11
**Do:** Write `docs/migrating-from-docker-hive.md`: the port map change, the execution engine
change (MapReduce → Tez), the service-user change (root → per-service), the HDFS permissions
change, the loss of Hue, and the **Spark 3.5.5 → 3.3.4 delta with its concrete consequences** —
Delta Lake 2.4.0 pairs with Spark 3.3.x so the predecessor's notebook JAR set is not directly
portable, and newer Spark Connect / ANSI-mode behaviours are absent.
Include a worked example: taking `map-reduce-example.ipynb` and running it against the new
cluster, naming exactly what must change.
**Done:** a reader who has never seen either project follows the guide and runs the notebook
against the new cluster without asking a question.

### T-P13 — [P] Suite runner
**FR:** FR-P13 · **Deps:** T-P03…T-P11
**Do:** `make test-parity` — runs all parity checks, reports per-check pass/fail and duration,
separate from the fast smoke suite.
**Done:** the suite runs standalone against a live cluster; a deliberately broken cluster
produces a specific failure, not a hang.

### T-P14 — [P] CI integration
**FR:** FR-P14, FR-P15 · **Deps:** T-P13, feature 001 T023
**Do:** Add the parity suite to the nightly workflow after the smoke suite. Upload
`make diagnose` output on failure. Include the ARM64 job once feature 002's T-A12 lands.
**Done:** nightly CI runs smoke then parity; both green on amd64; the ARM64 job runs green or
its manual procedure is documented with an owner (P5).

---

## Traceability

| FR | Tasks | | FR | Tasks |
|---|---|---|---|---|
| FR-P01 | T-P03 | | FR-P09 | T-P11 |
| FR-P02 | T-P01, T-P02, T-P04 | | FR-P10 | T-P12 |
| FR-P03 | T-P05 | | FR-P11 | T-P06, T-P12 |
| FR-P04 | T-P06 | | FR-P12 | T-P12 |
| FR-P05 | T-P07 | | FR-P13 | T-P13 |
| FR-P06 | T-P08 | | FR-P14 | T-P14 |
| FR-P07 | T-P09 | | FR-P15 | T-P14 |
| FR-P08 | T-P10 | | | |
