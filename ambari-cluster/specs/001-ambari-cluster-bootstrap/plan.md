# Implementation Plan — Feature 001

**Reads:** `spec.md` (requirements), `research.md` (decisions + spikes),
**`upstream-reference.md`** (the verified official procedure), `constitution.md`.
**Produces:** the runnable project. **Task list:** `tasks.md`.

> **Read `upstream-reference.md` before this file.** It transcribes the official Ambari
> quick-start procedure — base image, Compose keys, every install command — verified
> 2026-08-27. This plan automates that runbook; it does not invent an alternative to it.

---

## 1. Architecture

### 1.1 Runtime topology — `standard` profile

```
                              docker network: ambari-net
                              domain: .ambari.local
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌────────────────┐   ┌────────────────┐   ┌──────────────────────────────┐  │
│  │ repo           │   │ ambari-db      │   │ ambari-server                │  │
│  │ nginx          │   │ PostgreSQL     │   │ ambari-server 3.0.0          │  │
│  │ Ambari+Bigtop  │◄──┤ ambari schema  │◄──┤ Ambari Web  :8080            │  │
│  │ RPMs over HTTP │   │ hive  schema   │   │ REST /api/v1                 │  │
│  └───────┬────────┘   └────────────────┘   └───────────────┬──────────────┘  │
│          │ yum                                             │ heartbeat       │
│          │                        ┌────────────────────────┴───────────┐     │
│          │                        │                                    │     │
│  ┌───────▼────────────────────┐  ┌▼─────────────────┐  ┌───────────────▼──┐  │
│  │ master1.ambari.local       │  │ worker1          │  │ worker2          │  │
│  │ systemd + ambari-agent     │  │ systemd + agent  │  │ systemd + agent  │  │
│  │                            │  │                  │  │                  │  │
│  │ NameNode          :9870    │  │ DataNode  :9864  │  │ DataNode  :9864  │  │
│  │ ResourceManager   :8088    │  │ NodeManager:8042 │  │ NodeManager:8042 │  │
│  │ MR2 HistoryServer :19888   │  │                  │  │                  │  │
│  │ ZooKeeper Server  :2181    │  └──────────────────┘  └──────────────────┘  │
│  │ Hive Metastore    :9083    │                                              │
│  │ HiveServer2       :10000   │  ┌──────────────────────────────────────┐    │
│  │ AMS Collector     :6188    │  │ edge1  (optional)                    │    │
│  └────────────────────────────┘  │ client configs + Jupyter :8888       │    │
│                                  └──────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

Every box in the lower row is an Ambari **host**: a container built from
`bigtop/puppet:trunk-rockylinux-8`, running `/sbin/init` as PID 1 under `privileged: true`,
with `ambari-agent` registered. `repo`, `ambari-db`, and `ambari-server` are infrastructure,
not managed hosts.

**Hostnames use hyphens only** — `master1`, `worker1`, never `bigtop_hostname0`. Underscores
break `java.net.URI` and would reintroduce the `URISyntaxException` the predecessor already
fixed (decision D-011, failure mode F11).

### 1.1a Host container skeleton — verified against upstream

```yaml
master1:
  image: <project>/ambari-host:<pinned>     # FROM bigtop/puppet:trunk-rockylinux-8
  command: /sbin/init                        # systemd as PID 1
  privileged: true                           # upstream's answer; documented, not hidden
  hostname: master1
  domainname: ambari.local                   # → hostname -f = master1.ambari.local
  mem_limit: 6g
  mem_swappiness: 0
  networks:
    default:
      aliases: [master1.ambari.local]        # Docker DNS, NOT a hand-written /etc/hosts
```

Departures from upstream's Compose file, all deliberate and reasoned in
`upstream-reference.md` § Appraisal: hyphenated hostnames, Docker DNS instead of a
bind-mounted `/etc/hosts` with hardcoded IPs, a purpose-built image instead of `docker exec`
package installs, and no `version:` key.

### 1.2 Sizing profiles (FR-003)

| Profile | Hosts | Services | Target RAM | Use |
|---|---|---|---|---|
| `mini` | 1 all-in-one + infra | HDFS, YARN, MR2, ZooKeeper, Hive | ≤ 12 GB *(SPIKE-002)* | Laptop, classroom |
| `standard` | master1 + 2 workers + infra | above + Ambari Metrics, Tez | *(SPIKE-002)* | Default; the diagram above |
| `full` | master1 + 3 workers + edge1 + infra | above + HBase, Kafka, Spark, Zeppelin, Ranger | *(SPIKE-002)* | Workstation / CI |

Numbers are placeholders until SPIKE-002 is measured. **Do not publish them as fact before
then** (constitution P10).

### 1.3 Provisioning sequence

```
make up
  │
  ├─ 0. preflight        docker/compose present; RAM & disk vs profile; ports free
  ├─ 1. secrets          generate SSH keypair + DB/admin passwords → secrets/  (P7)
  ├─ 2. generate         cluster-topology.yaml → compose + blueprint + cluster template  (FR-002)
  ├─ 3. mirror           populate repo container from the version manifest (cached)  (FR-011)
  ├─ 4. build            build host images for the target platform
  ├─ 5. compose up       start repo, ambari-db, ambari-server, then all cluster hosts
  ├─ 6. gate: server     poll GET /api/v1/clusters until 200         (bounded, P6)
  ├─ 7. gate: hosts      poll GET /api/v1/hosts until N registered   (bounded, FR-014)
  ├─ 8. register repo    register the BIGTOP 3.3.0 repository version  (SPIKE-004)
  ├─ 9. POST blueprint   /api/v1/blueprints/<name>
  ├─ 10. POST cluster    /api/v1/clusters/<cluster>  (creation template → returns request id)
  ├─ 11. poll request    until COMPLETED; on FAILED, dump failed tasks  (FR-015, P6)
  └─ 12. report          name, hosts, services, elapsed, URLs, credentials  (FR-016)
```

Steps 6–11 are the contract in `contracts/ambari-rest.md`. Every gate has a timeout and a
diagnostic dump (P6).

### 1.4 Configuration flow — the core inversion

**Predecessor:**
```
hadoop-hive.env  →  entrypoint.sh sed  →  /etc/hadoop/core-site.xml
```
Config is a container-start side effect. Three drifted copies of the `sed` logic exist.

**This project:**
```
cluster-topology.yaml  →  blueprint configurations[]  →  Ambari  →  /etc/hadoop/conf/*.xml
```
Config is a first-class, versioned, Ambari-owned artifact. Constitution P1 forbids anything
else. A one-time migration tool (FR-017) bridges the two.

---

## 2. Project layout to be created

```
ambari-bigtop-cluster/
├── Makefile                        # the CLI surface (contracts/cli.md)
├── cluster-topology.yaml           # THE source of truth (contracts/cluster-topology.yaml)
├── versions.yaml                   # the single pinned version manifest (P3)
├── README.md
│
├── images/
│   ├── base/                       # FROM bigtop/puppet:trunk-rockylinux-8
│   │   ├── Dockerfile              #   + JDK 8 & 17, sshd, python3-distro, utils  (D-010)
│   │   └── files/                  #   bakes in upstream-reference.md §4 as image layers
│   ├── ambari-server/              # base + ambari-server + python3-psycopg2
│   ├── ambari-agent/               # base + ambari-agent, self-registering  (D-004)
│   └── repo/                       # nginx + createrepo  (D-005)
│
├── tools/
│   ├── generate.py                 # topology → compose + blueprint + template  (FR-002)
│   ├── validate.py                 # topology validation  (FR-004)
│   ├── env2blueprint.py            # legacy hadoop-hive.env → configurations[]  (FR-017)
│   ├── provision.py                # the REST driver, steps 6–11  (FR-013)
│   ├── diagnose.py                 # failure dumps  (P6)
│   └── mirror.sh                   # populate the local repo  (FR-011)
│
├── templates/
│   ├── blueprint/                  # per-service configuration fragments
│   └── compose/
│
├── tests/
│   ├── smoke/                      # the five P8 checks  (FR-024)
│   └── fixtures/                   # ported from docker-hive  (feature 003)
│
├── docs/
│   ├── architecture.md
│   ├── ports.md                    # incl. docker-hive collision map  (F8)
│   ├── config-migration.md         # the FR-018 mapping table
│   └── troubleshooting.md          # research.md § failure modes  (FR-026)
│
└── .github/workflows/
    └── nightly-cluster.yml         # up → test → destroy on amd64  (FR-025)
```

### Language choice

Python 3 for `tools/`. Ambari's own stack scripts are Python, the REST driver needs real JSON
and polling logic, and `generate.py` needs YAML plus templating. Bash is retained only for
`mirror.sh`, which is genuinely a shell task.

---

## 3. Phases

Each phase ends at a demonstrable state. Do not start a phase whose blocking spikes are open.

### Phase 0 — Settle the foundations *(blocking; no dependents may start)*

**SPIKE-003 and SPIKE-005 are resolved** (2026-08-27, from upstream). What remains:

- **Verify** the `bigtop/puppet:trunk-rockylinux-8` + `/sbin/init` + `privileged: true`
  container reaches `systemctl is-system-running == running` on cgroup v1, cgroup v2, and
  Docker Desktop macOS. This is confirmation, not discovery.
- **Resolve SPIKE-004** — the REST payload shapes and the confirmed stack identifier. Upstream's
  quick-start ends at the Ambari Web wizard and does not cover blueprints, so this must come
  from a live server: record `GET /api/v1/stacks` from a running Ambari 3.0.0.
- **Measure** the mirror size (part of SPIKE-005's remainder).

Amend `research.md` with every finding before proceeding.

### Phase 1 — Infrastructure

`repo`, `ambari-db`, `ambari-server` containers. `versions.yaml`. `mirror.sh`.
**Demonstrable:** Ambari Web reachable at `:8080`; `GET /api/v1/stacks` lists BIGTOP.

### Phase 2 — Hosts and registration

The `ambari-agent` image; FQDN and network aliasing; agent self-registration. Resolves
**SPIKE-001**.
**Demonstrable:** `GET /api/v1/hosts` lists every host by FQDN, all healthy.

### Phase 3 — Generation

`cluster-topology.yaml` schema, `validate.py`, `generate.py`, `env2blueprint.py`, the
migration mapping table.
**Demonstrable:** editing the topology regenerates compose + blueprint deterministically;
validation rejects each error class in FR-004 with a specific message.

### Phase 4 — Headless install

`provision.py`: the full REST sequence with bounded gates and failure dumps.
**Demonstrable:** `make up` from cold produces a `STARTED` cluster with no manual input.

### Phase 5 — Lifecycle and diagnostics

`down`, `destroy`, `status`, `logs`, `diagnose`, `shell`. Volume persistence. Idempotency.
**Demonstrable:** every FR-021/FR-022 path tested; an induced failure produces a useful dump.

### Phase 6 — Verification and docs

The five smoke checks, the nightly CI workflow, the README, the port map, the troubleshooting
guide, the migration guide.
**Demonstrable:** `make test` green; CI green; acceptance criteria 1–9 all satisfied.

### Phase 7 — Handoff to features 002 and 003

Sizing profiles measured (SPIKE-002, SPIKE-006) and published as real numbers.

---

## 4. Risk register

*Updated 2026-08-27 after the upstream documentation pass.*

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| ~~systemd-in-Docker not portable~~ | — | **Retired** | Upstream uses `privileged: true`; no cgroup branching needed |
| ~~Agent self-registration unworkable~~ | — | **Low** | Confirmed as upstream's own mechanism; only retry/hostname behaviour left to verify |
| ~~No Rocky 8 builds~~ | — | **Retired** | Rocky 8 *and* 9 confirmed published |
| No aarch64 packages at the Ambari distribution site | Feature 002 must source them elsewhere; P5 release gate at risk | Certain | Bigtop supports AArch64 and ships ARM host + build images. Feature 002 T-A01a checks Bigtop's own repo first — minutes of work, and it decides whether this is a week or a month |
| `standard` profile exceeds laptop RAM | Project misses its audience | **High** | SPIKE-002 early; upstream's 8 GB is pre-install and optimistic; `mini` collapses to one host |
| `apache-ambari.com` slow, rate-limited, or gone | Cannot build at all | Medium | D-005 mirror; FR-012 offline rebuild; commit the mirror manifest with checksums (F13) |
| Install duration makes iteration painful | Slow development, slow CI | High | Local mirror (D-005); image layer caching; `mini` for iteration |
| Ambari 3.0 blueprint/REST documentation gaps | Slow discovery | High | Upstream's quick-start stops at the web wizard; introspect the running server (SPIKE-004 method) |
| Packages unsigned (`gpgcheck=0`), MD5 only | Supply-chain exposure | Certain | Verify against published `MD5SUMS.txt` at mirror time; state the limitation in the README |

---

## 5. What is deliberately *not* built

Per `spec.md` § 6 — no Kerberos, no HA, no rolling upgrade, no Hue, no aarch64 package
building (feature 002), no parity fixtures (feature 003). Adding any of these to feature 001
is scope creep and should be rejected in review.
