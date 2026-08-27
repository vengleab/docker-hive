# Quickstart — the walkthrough that must work when feature 001 is done

> This describes software that **does not exist yet**. It is the acceptance walkthrough: when
> every step below works end to end, exactly as written, on a machine that has never run this
> project, feature 001 is complete.
>
> It doubles as the draft of the project README's getting-started section (FR-026).

---

## Prerequisites

- Docker Engine 24+ or Docker Desktop 4.30+, with Compose v2
- `make`
- Free RAM per profile — **placeholder pending SPIKE-002; measure before publishing**
- ~40 GB free disk (host images + package mirror + HDFS data)
- `linux/amd64` or `linux/arm64`

## 1. Clone and inspect

```bash
git clone <repo-url> ambari-bigtop-cluster
cd ambari-bigtop-cluster
cat cluster-topology.yaml
```

Everything about the cluster's shape is in that one file (constitution P2). Nothing else needs
editing for the default cluster.

## 2. Preflight

```bash
make preflight
```

```
[00:00:02] preflight  ✔ docker 27.3.1, compose v2.29.7
[00:00:03] preflight  ✔ cgroup v2 detected — using cgroupns host mode
[00:00:03] preflight  ✔ 32 GB RAM available (profile 'standard' needs 20 GB)
[00:00:04] preflight  ✔ 128 GB disk free
[00:00:04] preflight  ✔ ports 8080,19870,18088,19888,20000 free
[00:00:04] preflight  ✔ platform linux/arm64
```

Catches the expensive failures before anything is built. If it reports insufficient RAM,
switch `profile:` to `mini` and re-run.

## 3. Bring the cluster up

```bash
make up
```

First run downloads the package mirror and builds four images — the slow part. Subsequent
runs reuse both.

```
[00:00:12] secrets      ✔ generated 4 secrets → secrets/
[00:00:14] generate     ✔ 2 host groups → 3 hosts; blueprint 'bigtop-dev-blueprint'
[00:02:31] mirror       ✔ 1,247 packages (cached, 0 downloaded)
[00:06:48] build        ✔ 4 images (linux/arm64)
[00:07:02] compose      ✔ 6 containers started
[00:08:44] gate:server  ✔ Ambari server ready
[00:09:51] gate:hosts   ✔ 3/3 hosts registered and HEALTHY
[00:09:58] install      ⏳ INSTALLING   14%  (8/60)   DATANODE on worker1.ambari.local
[00:22:15] install      ⏳ STARTING     78%  (47/60)  HIVE_SERVER on master1.ambari.local
[00:31:22] install      ✔ COMPLETED (60/60 tasks)

Cluster 'bigtop-dev' is INSTALLED and STARTED
  Hosts     3 (master1, worker1, worker2)  ·  Services  6  ·  Elapsed  00:31:22

  Ambari Web        http://localhost:8080     admin / see secrets/ambari-admin-password
  NameNode          http://localhost:19870
  ResourceManager   http://localhost:18088
  JobHistory        http://localhost:19888
  HiveServer2       jdbc:hive2://localhost:20000/default

  Next: make test
```

No prompts, no wizard, no XML edited by hand.

## 4. Verify

```bash
make test
```

```
✔ hdfs-roundtrip         write, read, checksum          4.2s
✔ yarn-mapreduce-pi      job SUCCEEDED                 48.1s
✔ hive-beeline-ddl       CREATE / INSERT / SELECT      31.7s
✔ spark-submit-yarn      job SUCCEEDED                 62.3s
✔ ambari-service-checks  6/6 services passed           88.9s

5 passed, 0 failed  (3m55s)
```

These are the five checks constitution P8 fixes as the minimum bar.

## 5. Look around

```bash
make open          # Ambari Web
make status
```

```
Cluster bigtop-dev   BIGTOP-3.3.0   provisioning_state=INSTALLED

HOST                    STATUS   ARCH      MEM     COMPONENTS
master1.ambari.local    HEALTHY  aarch64   6.0 GB  16
worker1.ambari.local    HEALTHY  aarch64   4.0 GB   6
worker2.ambari.local    HEALTHY  aarch64   4.0 GB   6

SERVICE       STATE     HEALTH
HDFS          STARTED   ✔
YARN          STARTED   ✔
MAPREDUCE2    STARTED   ✔
ZOOKEEPER     STARTED   ✔
HIVE          STARTED   ✔
AMBARI_METRICS STARTED  ✔
```

In Ambari Web you can see the host list, the service list, per-component health, and the
configuration Ambari owns — the things the predecessor project could not show at all.

## 6. Do the thing the old project could not (scenario S3)

In Ambari Web: **Services → HDFS → Stop**. Watch HDFS go red and dependent services report
degraded. Then **Start**, and watch recovery.

Or over REST:

```bash
curl -u admin:$(cat secrets/ambari-admin-password) \
     -H "X-Requested-By: ambari" -X PUT \
     -d '{"RequestInfo":{"context":"Stop HDFS"},"ServiceInfo":{"state":"INSTALLED"}}' \
     http://localhost:8080/api/v1/clusters/bigtop-dev/services/HDFS
```

**This is the lesson.** In `docker-hive`, "restart the DataNode" means `docker restart` — a
container operation that tells you nothing about how a cluster behaves. Here it is a cluster
operation with real consequences you can observe.

## 7. Reshape the cluster (scenario S2)

Edit `cluster-topology.yaml`:

```yaml
profile: mini            # was: standard
services:
  - HDFS
  - YARN
  - MAPREDUCE2
  - ZOOKEEPER
  - HIVE
  - HBASE                # added
```

```bash
make validate     # V1-V10; catches e.g. HBASE without ZOOKEEPER before anything runs
make destroy
make up
```

One file changed. No Dockerfile written, no image rebuilt by hand, no entrypoint edited.

## 8. Run a workload from the old project (scenario S5)

```bash
make shell HOST=master1

hdfs dfs -mkdir -p /data
hdfs dfs -put /etc/passwd /data/passwd
hdfs dfs -cat /data/passwd | head

beeline -u 'jdbc:hive2://master1.ambari.local:10000/default'
  CREATE TABLE demo (id INT, name STRING);
  INSERT INTO demo VALUES (1, 'ambari');
  SELECT * FROM demo;
```

Feature 003 turns this into automated parity fixtures ported from `docker-hive`'s notebook and
`spark_yarn_test.py`.

## 9. Stop and clean up

```bash
make down        # stop, keep data
make up          # back where you were, fast — no reinstall
make destroy     # remove everything including volumes
```

---

## When something fails

```bash
make diagnose
```

Produces `diagnostics-<timestamp>.tar.gz` with every container's logs, the Ambari server and
agent logs, the failed-task dump, and per-host `hostname -f` / `systemctl is-system-running` /
clock-skew checks — the three things (failure modes F1, F4, F5) that account for most
first-run failures. Secrets are redacted.

The catalogue of known failure modes and their fixes is `docs/troubleshooting.md`, derived
from `research.md`.

---

## Acceptance checklist

Feature 001 is done when every one of these is true on a clean machine:

- [ ] Steps 1–9 work exactly as written, with no undocumented step
- [ ] `make up` needs no interactive input *(FR-013)*
- [ ] `make test` passes 5/5 *(FR-024)*
- [ ] `make up` twice in a row succeeds *(FR-021)*
- [ ] `make destroy && make up` succeeds with upstream mirrors unreachable *(FR-012)*
- [ ] `make down && make up` preserves HDFS data *(FR-022)*
- [ ] Step 7's profile change works with no other file edited *(FR-001, FR-003)*
- [ ] An induced failure produces a dump naming the host and component *(FR-015)*
- [ ] `grep -rE "sed .*(core|hdfs|yarn|mapred|hive)-site" .` returns nothing *(P1)*
- [ ] Every `SPIKE-###` is resolved or explicitly deferred with an owner *(P10)*
- [ ] The suite passes on both `linux/amd64` and `linux/arm64` *(P5, feature 002)*
