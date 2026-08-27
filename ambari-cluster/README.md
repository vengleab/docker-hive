# ambari-bigtop-cluster — specification package

> **Status: specifications only. No implementation exists yet.**
>
> ### This package is self-contained by design
>
> It is the *seed of a new standalone repository*. Copy it anywhere — into an empty repo, onto
> another machine — and it remains **fully executable**:
>
> ```bash
> cp -r ambari-cluster/ ~/ambari-bigtop-cluster/    # nothing else needed
> ```
>
> - **No file outside this directory is required.** Every input the tasks need — the legacy
>   configuration to migrate, the test fixtures, the port map, the expected outputs — is
>   embedded under `reference/predecessor/`.
> - **No reference cluster is required.** Parity baselines are computed from committed inputs,
>   not captured from a running deployment.
> - The predecessor project is discussed throughout as *prior art*, and its files are cited by
>   name so the reasoning is traceable. That is documentation, not a dependency.
>
> This is constitution **P9**, and it is enforced by a script that ships here:
>
> ```bash
> ./check-standalone.sh                                  # verify in place
> cp -r . /tmp/x && cd /tmp/x && ./check-standalone.sh   # verify after moving
> ```
>
> The second form is the one that matters. A task saying *"copy this file from the old
> project"* contains no bad path and passes any grep — it just fails later, for whoever tries
> to run it.

## What this project will be

A reproducible, containerised **Apache Hadoop cluster provisioned and managed by Apache
Ambari** — instead of installed by hand.

The predecessor project (`docker-hive`) builds its cluster manually: one hand-written
container per Hadoop daemon, with configuration `sed`-injected into XML by a shell
entrypoint. It works, and it teaches the *components* well — but it teaches nothing about
*operating a cluster*, and it cannot grow past one daemon per container.

This project replaces that with the real thing:

| | `docker-hive` (predecessor) | `ambari-bigtop-cluster` (this project) |
|---|---|---|
| Install method | Tarballs unpacked in Dockerfiles | RPM packages from a Bigtop repository |
| Configuration | `sed` into XML from `hadoop-hive.env` | Ambari blueprint `configurations[]` |
| Topology | One daemon per container, fixed | Declarative `cluster-topology.yaml`, N hosts |
| Lifecycle | `docker compose up` | Ambari server + agents, service start/stop/restart |
| Observability | Per-daemon web UIs only | Ambari Web + Ambari Metrics + per-daemon UIs |
| Adding a service | Write a new Dockerfile | Add a component to a host group |

## The stack

**Apache Ambari 3.0.0** managing the **Apache Bigtop 3.3.0** stack.

This combination is deliberate: it is fully open — no Cloudera subscription, no paywalled HDP
repositories — and Bigtop 3.3.0 ships **Hadoop 3.3.6** and **Hive 3.1.3**, the exact versions
`docker-hive` runs today. That makes workload parity a testable acceptance criterion rather
than an aspiration.

| Component | Version | | Component | Version |
|---|---|---|---|---|
| Hadoop | 3.3.6 | | Tez | 0.10.2 |
| Hive | 3.1.3 | | Ranger | 2.4.0 |
| Spark | 3.3.4 | | Zeppelin | 0.11.0 |
| HBase | 2.4.17 | | Solr | 8.11.2 |
| ZooKeeper | 3.7.2 | | Kafka | 2.8.2 |
| Flink | 1.16.2 | | Livy | 0.8.0 |
| Phoenix | 5.1.3 | | Alluxio | 2.9.3 |

> **Accepted regression:** Spark drops from 3.5.5 (predecessor) to 3.3.4 (Bigtop 3.3.0).
> Ambari-managed lifecycle is worth more here than two Spark minor versions. See
> `specs/001-ambari-cluster-bootstrap/research.md` § D-002.

## How to consume these specs

Read them in this order:

0. **`specs/001-ambari-cluster-bootstrap/upstream-reference.md`** — the official Apache Ambari
   Docker + installation procedure, transcribed and verified 2026-08-27, with an appraisal of
   what this project adopts from it and what it deliberately rejects. This project **automates
   upstream's manual runbook**; read it to know what the runbook actually is.
1. **`.specify/memory/constitution.md`** — the non-negotiable principles. Every task must
   obey these. Read it first and do not violate it without an explicit, recorded amendment.
2. **`specs/001-ambari-cluster-bootstrap/spec.md`** — *what* is being built and *why*, as
   numbered functional requirements (`FR-###`) with acceptance criteria.
3. **`specs/001-ambari-cluster-bootstrap/research.md`** — the decisions already made, the
   alternatives already rejected, and — importantly — the **open spikes** (`SPIKE-###`) that
   must be resolved by measurement before the design can be trusted.
4. **`specs/001-ambari-cluster-bootstrap/plan.md`** — the technical architecture and the
   project's file layout.
5. **`specs/001-ambari-cluster-bootstrap/contracts/`** — the interfaces: the topology input
   format, the blueprint shape, the Ambari REST sequence, the CLI surface.
6. **`specs/001-ambari-cluster-bootstrap/tasks.md`** — the ordered, executable task list.
   **Start here when you begin implementing.**

Then the two dependent features:

- **`specs/002-arm64-stack-enablement/`** — making `linux/arm64` a first-class target.
  The Ambari download page states that *"all packages are built for x86_64 architecture"* —
  but that is the **distribution site's** build capacity, not a limitation of Apache Bigtop,
  which supports AArch64 and already ships an ARM host image and ARM build environment for
  this exact stack. Start at **T-A01a**: it takes minutes and decides whether this feature is
  a week or a month.
- **`specs/003-workload-parity-validation/`** — proving the new cluster actually runs the
  predecessor's workloads.

### Rules for the implementing agent

- **Resolve the spikes first.** `research.md` marks every claim that was *not* verified
  during specification. Several of them (aarch64 package availability, cgroup v2 behaviour,
  exact Ambari 3.0 REST payload shapes) can invalidate parts of the design. The first tasks
  in `tasks.md` exist to settle them. Do not build on an unresolved spike.
- **Do not silently change a decision.** If a spike disproves a decision in `research.md`,
  amend `research.md` — record the finding, the new decision, and the date — then proceed.
- **Traceability is mandatory.** Every task cites the `FR-###` it satisfies. Every commit
  cites the `T###` it completes.
- **Never add a dependency on the predecessor.** Not a path, and not an instruction like
  "copy this from `docker-hive`" or "run this against the old cluster" — the second fails just
  as hard, only later. If a task needs something not already in `reference/predecessor/`, copy
  it in and update that directory's index. Constitution P9.

## Layout

```
.
├── README.md                      ← you are here
├── check-standalone.sh            enforces P9 — run it after moving the package
├── .gitignore
├── .specify/memory/constitution.md
├── reference/
│   └── predecessor/               everything the tasks need from the prior project,
│       ├── README.md              embedded so this package stands alone (P9)
│       ├── hadoop-hive.env            legacy config to migrate      → 001 T014
│       ├── entrypoint-configure.sh    the sed mechanism replaced    → 001 T014
│       ├── spark_yarn_pi.py           Spark-on-YARN fixture         → 003 T-P07
│       ├── submit_yarn.sh             its submit wrapper            → 003 T-P07
│       ├── notebook-workload.md       the workload to rebuild       → 003 T-P02
│       └── topology-and-ports.md      port map, versions, topology  → 001 FR-023
└── specs/
    ├── 001-ambari-cluster-bootstrap/
    │   ├── spec.md            what & why — FR-### and acceptance criteria
    │   ├── plan.md            how — architecture, phases, file layout
    │   ├── research.md        decisions (D-###), rejected alternatives, spikes (SPIKE-###)
    │   ├── data-model.md      the entities and their relationships
    │   ├── upstream-reference.md  the official Ambari procedure, verified + appraised
    │   ├── quickstart.md      the end-to-end walkthrough that must work when done
    │   ├── contracts/
    │   │   ├── cluster-topology.yaml   the declarative input contract
    │   │   ├── blueprint.md            Ambari blueprint + creation template contract
    │   │   ├── ambari-rest.md          the headless install REST sequence
    │   │   └── cli.md                  the Makefile / CLI surface
    │   └── tasks.md           T### — ordered, executable
    ├── 002-arm64-stack-enablement/
    │   ├── spec.md
    │   ├── research.md
    │   └── tasks.md
    └── 003-workload-parity-validation/
        ├── spec.md
        └── tasks.md
```

## Provenance

Upstream procedure verified 2026-08-27 against the Apache Ambari website's own source
(`apache/ambari-website`, branch `main`) — see `upstream-reference.md`.

Specification drafted against `docker-hive` @ `b2da7c2`. The predecessor is credited as prior
art for its port allocation map, its readiness-gating pattern, its Hive metastore schema
bundle, and its two smoke-test fixtures — all of which these specs reuse.
