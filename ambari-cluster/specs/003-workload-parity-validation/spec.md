# Feature 003 — Workload parity validation

**Status:** Draft · **Depends on:** 001 · **Related:** 002 (the suite must pass on both
architectures)

---

## 1. Why

A rewrite is only a replacement if the old work still runs on it. Otherwise it is a second,
parallel system, and users are left maintaining both.

`docker-hive` has real workloads: a 38-cell MapReduce/RDD teaching notebook, a Spark-on-YARN
Pi job with Hive support enabled, and a set of tuning values chosen deliberately. If a student
cannot bring their notebook across, the Ambari cluster has not replaced anything.

The version alignment makes this a fair test rather than a hopeful one. Bigtop 3.3.0 ships
**Hadoop 3.3.6** and **Hive 3.1.3** — byte-identical to what `docker-hive` runs. There is no
version excuse available. If a Hive query or a MapReduce job behaves differently, that is a
provisioning defect in this project, not a version difference.

Spark is the exception and the one honest caveat: 3.5.5 → 3.3.4 (decision D-002). This feature
is where that difference stops being a footnote and gets measured.

## 2. Scope

**In:** functional equivalence for HDFS, YARN, MapReduce, and Hive; Spark equivalence within
the version delta; the deliberate tuning values; native library coverage.

**Out:** performance benchmarking (feature 002 covers native-vs-emulated), migrating user data,
Hue (dropped, D-008), and anything requiring Spark features that do not exist in 3.3.4.

## 3. Fixtures — embedded, not referenced

Every input this feature needs is already inside this package, under
`reference/predecessor/`. **No task here requires the predecessor repository, and none
requires a running predecessor cluster** (constitution P9).

| Source — in this package | Becomes | Tests |
|---|---|---|
| `reference/predecessor/spark_yarn_pi.py` | `tests/fixtures/spark_yarn_pi.py` | Spark on YARN with `enableHiveSupport()` |
| `reference/predecessor/submit_yarn.sh` | `tests/fixtures/submit_yarn.sh` | `spark-submit --master yarn --deploy-mode client` |
| `reference/predecessor/notebook-workload.md` | `tests/fixtures/mapreduce_wordcount.py` | Written from that description — RDD word count over HDFS |
| *(written fresh)* | `tests/fixtures/wordcount/` + jar | Built from committed source; a committed binary is not reproducible (P3) |
| `reference/predecessor/hadoop-hive.env` | `tests/fixtures/legacy-hadoop-hive.env` | Input to the config-migration assertions |
| *(written fresh)* | `tests/fixtures/films.csv` + `expected/wordcount.txt` | The deterministic parity input and its computed expectation |

### Why the baseline is computed rather than captured

The predecessor's notebook reads `hdfs://namenode:9000/data/films`, and **that dataset is not
in its repository** — its `.gitignore` is the single line `data`. Anyone cloning it hits the
same wall.

An earlier draft of this feature required output "byte-identical to the same job on
`docker-hive`", which nobody could actually verify. This feature instead **generates its own
fixed input and commits the expected output**. The transformation is pure and the input is
committed, so the result is fully determined — determinism comes from the fixture, not from a
reference cluster.

The notebook itself is not copied: it is an interactive teaching artefact, and what this
feature needs is the workload. `reference/predecessor/notebook-workload.md` describes its
operations precisely enough to rebuild headlessly, and notes what a ported notebook would need
if one is carried onto the optional `edge` host.

## 4. Functional requirements

### Core equivalence

- **FR-P01** HDFS: write, read back, and verify checksum for a file of at least 100 MB across
  multiple blocks. Confirm the block count matches the configured block size and that
  replication matches `dfs.replication`.
- **FR-P02** YARN/MapReduce: the ported WordCount job reaches `SUCCEEDED` and produces output
  byte-identical to the same job on `docker-hive`.
- **FR-P03** Hive: `CREATE DATABASE` / `CREATE TABLE` / `INSERT` / `SELECT` / `JOIN` /
  `DROP` via Beeline against HiveServer2, including a partitioned table and an ACID
  transactional table — `docker-hive` enables `hive.txn.manager` and the compactor, so ACID is
  in scope, not optional.
- **FR-P04** Hive-on-Tez: a query executes on Tez and completes. `docker-hive` runs Hive on
  MapReduce; Tez is what Ambari's stack configures. **Behaviour must be equivalent even though
  the engine differs** — this is exactly the kind of difference that would otherwise surface as
  a mysterious student bug.
- **FR-P05** Spark on YARN: the ported Pi job runs with `--master yarn --deploy-mode client`
  and reaches `SUCCEEDED`.
- **FR-P06** Spark-Hive integration: `SparkSession` with `enableHiveSupport()` reads a table
  created through Beeline, and vice versa. This is `docker-hive`'s flow 4 ("Spark over Hive")
  and its most fragile integration point.
- **FR-P07** Compression: a MapReduce job with Snappy map-output compression completes and
  produces correct results. `hadoop checknative -a` reports Snappy available.
  *(`docker-hive` sets `io.compression.codecs` to SnappyCodec and enables map-output
  compression — a silent fallback here would look like success and be wrong.)*

### Configuration parity

- **FR-P08** Every tuning value in `docs/config-migration.md`'s "carried over" column is
  asserted present in the running cluster's effective configuration, read from Ambari's API —
  not merely present in the blueprint.
- **FR-P09** Every value in the "dropped" column is asserted **absent or overridden**,
  confirming the deliberate departures actually took effect. In particular
  `dfs.permissions.enabled` must **not** be `false`.

### Documented differences

- **FR-P10** The Spark 3.5.5 → 3.3.4 delta is documented with the concrete consequences: Delta
  Lake 2.4.0 pairs with Spark 3.3.x rather than 3.5.x, so `docker-hive`'s notebook JAR set is
  not directly portable; newer Spark Connect and ANSI-mode behaviours are absent.
- **FR-P11** Every behavioural difference found during this feature is documented in a
  migration guide — the Tez-vs-MapReduce execution engine change, the service-user change
  (root → per-service users), the HDFS permissions change, the port changes, and the loss of
  Hue.
- **FR-P12** A `docker-hive` user MUST be able to follow that guide and run their existing
  notebook against the new cluster, with the guide stating plainly what they must change.

### Execution

- **FR-P13** The parity suite runs as `make test-parity`, separately from the fast smoke suite,
  and reports per-check pass/fail with durations.
- **FR-P14** The suite runs in the nightly CI workflow after the smoke suite.
- **FR-P15** The suite passes on both `linux/amd64` and `linux/arm64` (constitution P5).

## 5. Acceptance criteria

1. `make test-parity` passes every check on a `standard` cluster.
2. The ported WordCount produces output identical to `docker-hive`'s, compared byte for byte.
3. The ported Spark Pi job succeeds on YARN with Hive support enabled.
4. A table created in Beeline is readable from Spark, and the reverse. *(FR-P06)*
5. `hadoop checknative -a` reports Snappy available; a Snappy-compressed job succeeds.
   *(FR-P07)*
6. Every "carried over" configuration value is verified present via Ambari's API; every
   "dropped" value is verified absent. *(FR-P08, FR-P09)*
7. The migration guide is complete, and a reader following it runs their existing notebook
   against the new cluster. *(FR-P12)*
8. The suite passes on both architectures. *(FR-P15)*
9. No fixture references `../docker-hive`. *(P9)*

## 6. Why this feature is not optional

Without it, "Ambari-managed replacement for `docker-hive`" is a claim rather than a fact. The
version alignment removes every excuse: identical Hadoop, identical Hive. Anything that
behaves differently is this project's defect, and this suite is what finds it — before a
student does.
