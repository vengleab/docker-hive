# Feature 001 — Ambari Cluster Bootstrap

**Status:** Draft · **Owner:** unassigned · **Depends on:** none · **Blocks:** 002, 003

---

## 1. Why

`docker-hive` provisions its Big Data stack by hand. Each Hadoop daemon has a bespoke
Dockerfile; each configuration property is `sed`-injected into XML by a shell entrypoint from
a flat `hadoop-hive.env` file. There is no ZooKeeper, no service lifecycle, no host concept,
no way to add a node, and no way to add a service without writing a new container image.

The result is a good demonstration of Hadoop's *components* and a poor demonstration of a
Hadoop *cluster*. Learners come away able to start containers, not able to operate a
cluster — which is the skill the tooling exists to teach.

This feature replaces manual installation with **Apache Ambari 3.0.0 provisioning the Apache
Bigtop 3.3.0 stack**: real RPM packages, real host agents, a real blueprint, a real service
lifecycle, and a management UI — all still fitting on a laptop via Docker.

## 2. What success looks like

A user with Docker and `make` runs one command and, without further input, gets a running
multi-node Hadoop cluster they can manage from Ambari Web.

```
$ make up
...
Cluster 'bigtop-dev' is INSTALLED and STARTED (7 hosts, 6 services, 00:23:41)
Ambari Web:  http://localhost:8080   (admin / see secrets/ambari-admin-password)
NameNode:    http://localhost:9870
ResourceMgr: http://localhost:8088
$ make test
✔ hdfs-roundtrip        ✔ yarn-mapreduce-pi     ✔ hive-beeline-ddl
✔ spark-submit-yarn     ✔ ambari-service-checks
5 passed, 0 failed
```

## 3. User scenarios

### S1 — First-time learner brings up a cluster

A student clones the repo on a laptop, runs `make up`, waits, and opens Ambari Web. They see
a host list, a service list with green health indicators, and can stop and restart HDFS from
the UI. They never edit an XML file.

**Acceptance:** cold clone → running cluster with zero manual configuration and zero
interactive prompts.

### S2 — Instructor tailors the cluster

An instructor wants a smaller cluster for a low-RAM classroom, and wants HBase added for a
later lesson. They edit `cluster-topology.yaml`: switch the profile to `mini`, add `HBASE` to
the service list, and re-run `make up`. Nothing else changes.

**Acceptance:** topology and service set are changed by editing one declarative file.

### S3 — Learner breaks a service and recovers it

A student stops the DataNode from Ambari Web and watches HDFS go to a degraded state, then
restarts it and watches it recover. This is the lesson that the predecessor project could not
teach at all.

**Acceptance:** service stop/start/restart works from Ambari Web and from the REST API, and
health state reflects reality.

### S4 — Apple Silicon user

A user on an M-series Mac runs the identical `make up` and gets a natively-running cluster,
not an emulated one.

**Acceptance:** the smoke suite passes on `linux/arm64` (delivered by feature 002).

### S5 — Existing docker-hive user migrates a workload

A user takes their existing PySpark notebook and MapReduce job from `docker-hive` and runs
them against the new cluster unchanged apart from connection endpoints.

**Acceptance:** the parity suite passes (delivered by feature 003).

## 4. Functional requirements

### Topology and generation

- **FR-001** The system MUST accept a single declarative `cluster-topology.yaml` describing
  host groups, per-group components, enabled services, sizing, and the cluster name.
  Contract: `contracts/cluster-topology.yaml`.
- **FR-002** The system MUST generate the Docker Compose file, the Ambari blueprint, and the
  Ambari cluster creation template from `cluster-topology.yaml`. Generation MUST be
  deterministic: identical input produces byte-identical output.
- **FR-003** The system MUST provide at least three named sizing profiles — `mini`,
  `standard`, `full` — selectable from `cluster-topology.yaml`, with documented RAM/CPU/disk
  requirements for each.
- **FR-004** The system MUST validate `cluster-topology.yaml` before generating anything, and
  MUST reject with a specific, actionable message: unknown components, components placed on
  more hosts than the service permits, missing required dependencies (e.g. HBase without
  ZooKeeper), and cardinality violations (e.g. two NameNodes without HA).

### Host images and runtime

- **FR-005** Every cluster host MUST be a container built from
  **`bigtop/puppet:trunk-rockylinux-8`** running **`/sbin/init`** as PID 1 under
  **`privileged: true`**, so that Ambari can manage services through `systemctl` exactly as it
  would on a physical host. *(Upstream's own configuration — `upstream-reference.md` § 1.)*
- **FR-006** The host image MUST work on cgroup v1 hosts, cgroup v2 hosts (Linux 6.x), and
  Docker Desktop on macOS. `privileged: true` is expected to make this uniform; the README MUST
  state the privilege requirement and its security implication plainly rather than burying it.
- **FR-006a** The host image MUST install **both JDK 8 and JDK 17** and MUST pass them
  separately at `ambari-server setup` — Java 17 as `--ambari-java-home` for Ambari itself,
  Java 8 as `-j` for the managed stack. *(Decision D-010; failure mode F12.)*
- **FR-007** Every cluster host MUST have a resolvable **fully-qualified domain name**, MUST
  return that FQDN from `hostname -f`, and MUST be resolvable by that FQDN from every other
  host and from the Ambari server. Resolution MUST use Docker's embedded DNS and network
  aliases; the system MUST NOT write a hosts file with hardcoded IPs.
- **FR-007a** Every generated hostname, FQDN label, network name, and Compose project name
  MUST match `[a-z0-9]([a-z0-9-]*[a-z0-9])?` — **underscores are forbidden**. *(Decision
  D-011; failure mode F11; validation rule V7.)*
- **FR-008** `ambari-agent` MUST be pre-installed in the host image and MUST self-register
  with the Ambari server on boot. The SSH-based host bootstrap wizard MUST NOT be on the
  happy path.
- **FR-009** An SSH daemon MUST be available on cluster hosts for debugging, with a keypair
  generated at first `make up` into gitignored `secrets/`. It MUST NOT be required for
  provisioning.

### Package distribution

- **FR-010** The system MUST run a local package-repository container serving the Ambari 3.0.0
  and Bigtop 3.3.0 RPMs over HTTP to all cluster hosts, mirrored from
  `apache-ambari.com/dist/{ambari/3.0.0,bigtop/3.3.0}/rocky8/`.
- **FR-011** The repository contents MUST be populated from a single pinned version manifest,
  and the population step MUST be cacheable so that repeat builds do not re-download.
  The upstream host is community-run and explicitly bandwidth-constrained; re-downloading on
  every build is not acceptable behaviour toward it.
- **FR-011a** Mirrored packages MUST be verified against the published `MD5SUMS.txt`. Upstream
  serves the repository with `gpgcheck=0` and no signatures, so this is the only integrity
  check available, and the README MUST state that limitation.
- **FR-012** After the repository is populated once, a full `make destroy && make up` MUST
  succeed with no access to upstream package mirrors. **This is the highest-value requirement
  in this specification**: the sole distribution point is a single community-run server, and
  this requirement is what keeps the project buildable if it becomes slow or disappears.
  The mirror manifest with per-file checksums MUST be committed so a future rebuild remains
  verifiable.

### Provisioning

- **FR-013** The system MUST install the cluster **headlessly via the Ambari REST API**,
  using a blueprint and a cluster creation template. No interactive step, no browser.
  Contract: `contracts/ambari-rest.md`.
- **FR-014** The system MUST wait for every agent host to register before submitting the
  blueprint, with a bounded timeout and a diagnostic dump on expiry.
- **FR-015** The system MUST poll the Ambari install request to completion and MUST surface
  per-task failures — the failing host, the failing component, and the stderr tail — not just
  a non-zero exit code.
- **FR-016** The system MUST report a clear terminal state: cluster name, host count, service
  count, elapsed time, and the URLs and credentials for every exposed UI.

### Configuration migration

- **FR-017** The system MUST provide a tool that reads a legacy `hadoop-hive.env`-style file
  and emits the equivalent blueprint `configurations[]` blocks, correctly decoding the
  `_`→`.`, `___`→`-`, `__`→`_` encoding.
- **FR-018** The migrated configuration MUST preserve the predecessor's deliberate tuning:
  YARN NodeManager resources, MapReduce heap sizes, the capacity scheduler settings, log
  aggregation, and the timeline service. A mapping table MUST record each carried-over value
  and each deliberately dropped one, with reasons.
- **FR-019** Any predecessor setting that is unsafe or obsolete under Ambari MUST be
  explicitly listed as dropped, with the reason — including `POSTGRES_HOST_AUTH_METHOD=trust`
  and `dfs.permissions.enabled=false`.

### Lifecycle

- **FR-020** The system MUST expose `up`, `down`, `destroy`, `status`, `logs`, `diagnose`,
  `test`, and `shell` operations. Contract: `contracts/cli.md`.
- **FR-021** `make up` MUST be idempotent per constitution P4.
- **FR-022** HDFS NameNode and DataNode data, and the Ambari and Hive databases, MUST persist
  across `make down` / `make up` and MUST be removed by `make destroy`.
- **FR-023** The system MUST expose the standard web UIs on the host, with a documented port
  map that avoids collisions with a concurrently running `docker-hive`.

### Verification

- **FR-024** The system MUST provide a `make test` smoke suite covering, at minimum, the five
  checks named in constitution P8.
- **FR-025** The smoke suite MUST run in CI on `linux/amd64` on a schedule, executing the
  full `up` → `test` → `destroy` cycle.

### Documentation

- **FR-026** The project MUST ship a README with an architecture diagram, the port map, the
  sizing profiles with their real resource requirements, and a troubleshooting section
  covering the failure modes catalogued in `research.md`.
- **FR-027** The project MUST document, for a `docker-hive` user, what changed and why —
  including the Spark 3.5.5 → 3.3.4 regression.

## 5. Non-functional requirements

- **NFR-001** `make up` on the `standard` profile completes in **≤ 45 minutes** on a
  developer laptop with a warm package cache. *(Baseline to be measured — SPIKE-006.)*
- **NFR-002** The `mini` profile runs in **≤ 12 GB RAM**. *(To be measured — SPIKE-002.)*
- **NFR-003** All provisioning logic is idempotent and safely re-runnable after interruption.
- **NFR-004** No component requires credentials, subscriptions, or paywalled repositories.

## 6. Out of scope for this feature

| Excluded | Where it goes |
|---|---|
| aarch64 package availability and building | Feature 002 |
| Workload parity fixtures from `docker-hive` | Feature 003 |
| Kerberos / security enablement | Future feature; noted in `research.md` § Future |
| NameNode / ResourceManager HA | Future feature |
| Rolling upgrade of the stack | Future feature |
| Hue | Dropped — see `research.md` § D-008 |
| Replacing `docker-hive` | Never. The two coexist. |

## 7. Acceptance criteria

The feature is complete when **all** hold:

1. On a clean machine, `git clone && make up` produces a cluster in `INSTALLED`/`STARTED`
   state with no interactive input. *(FR-001, FR-013)*
2. `make test` passes all five smoke checks. *(FR-024)*
3. Ambari Web at `:8080` lists every host as healthy and every service as started. *(FR-005,
   FR-008)*
4. Stopping and restarting a service from Ambari Web works and is reflected in health state.
   *(S3)*
5. Changing the profile in `cluster-topology.yaml` from `standard` to `mini` and re-running
   produces a correspondingly smaller cluster with no other file edited. *(FR-001, FR-003)*
6. `make destroy && make up` succeeds with upstream package mirrors unreachable. *(FR-012)*
7. `grep -rE "sed .*(core|hdfs|yarn|mapred|hive)-site" .` returns nothing. *(P1)*
8. Every `SPIKE-###` in `research.md` is either resolved with a recorded finding or
   explicitly deferred with a recorded owner and date. *(P10)*
9. A deliberately induced failure (e.g. a host stopped mid-install) produces a diagnostic
   dump naming the failing host and component, not a bare stack trace. *(FR-015, P6)*
10. No generated hostname, FQDN, network name, or Compose project name contains an
    underscore. *(FR-007a; the predecessor's `URISyntaxException` does not recur)*
11. Both JDK 8 and JDK 17 are present on every host and are passed to the correct flags.
    *(FR-006a)*

## 8. Requirement → task traceability

Maintained in `tasks.md`; every `T###` cites the `FR-###` it satisfies. A requirement with no
task is a planning defect; a task with no requirement is scope creep.
