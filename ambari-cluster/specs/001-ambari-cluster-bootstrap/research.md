# Research — Feature 001

Decisions (`D-###`), rejected alternatives, spikes (`SPIKE-###`), and known failure modes.

> **Read this before writing any code.** Several spikes below can invalidate parts of the
> design. Constitution P10 requires that they be settled by measurement, not assumption.
>
> **Verification conditions at drafting time:** this specification was written in an
> environment with restricted outbound network access. Upstream repositories
> (`ambari.apache.org`, the Bigtop distribution mirrors) could **not** be fetched directly.
> Version facts below come from Apache release notes and project documentation retrieved via
> search; **directory-level package availability was not verified.** Every claim that depends
> on what is actually published is marked as a spike.

---

## Decisions

### D-001 — Apache Ambari 3.0.0 + Apache Bigtop 3.3.0

**Chosen.** Ambari 3.0.0 uses Bigtop as its default packaging system and targets the Bigtop
3.3.0 stack. Bigtop 3.3.0 ships Hadoop 3.3.6, Hive 3.1.3, Spark 3.3.4, HBase 2.4.17,
ZooKeeper 3.7.2, Tez 0.10.2, Ranger 2.4.0, Zeppelin 0.11.0, Solr 8.11.2, Kafka 2.8.2, Livy
0.8.0, Flink 1.16.2, Phoenix 5.1.3, Alluxio 2.9.3.

*Rationale:* fully open, no subscription. Hadoop 3.3.6 and Hive 3.1.3 are **the exact
versions `docker-hive` runs today**, which makes feature 003's parity claim testable rather
than aspirational.

**Rejected — Ambari 2.7.x + HDP 3.1.5.** The stack most tutorials assume, and the one with
the most community material. HDP binary repositories moved behind Cloudera paywalled
credentials in 2021. A project that cannot be built by a student without a vendor
subscription fails its own purpose.

**Rejected — Bigtop 3.2.0.** Superseded; older Hadoop (3.3.4) and Spark lines. Its only
advantage is a longer tail of blog posts.

**Rejected — Ambari + a hand-rolled custom stack definition.** Maximum control, and it would
let us keep Spark 3.5.5. It also means authoring and maintaining stack definitions, service
metainfo, and Python command scripts — a project in itself, and a large one. Revisit only if
Bigtop's component versions become a genuine blocker.

### D-002 — Accept the Spark 3.5.5 → 3.3.4 regression

Bigtop 3.3.0's Spark is 3.3.4; `docker-hive` runs 3.3.4's successor line at 3.5.5.

**Accepted.** The point of this project is Ambari-managed lifecycle, not the newest Spark.
Two Spark minor versions are a smaller loss than either abandoning Bigtop packaging or taking
on custom stack authoring (D-001's third rejected option).

Practical consequences the docs must state (FR-027): Delta Lake 2.4.0 pairs with Spark 3.3.x,
not 3.5.x, so `docker-hive`'s notebook JARs are not directly portable; some Spark Connect and
newer ANSI-mode behaviours are absent.

*Escape hatch:* Spark can be installed outside the Ambari-managed stack on an edge host if a
newer version is genuinely needed. This is explicitly **not** in feature 001's scope.

### D-003 — Containers running systemd, not one-process containers

Every cluster host is a Rocky Linux 8 container with `/sbin/init` as PID 1.

*Rationale:* Ambari manages component lifecycle through `systemctl`. It was built for real
hosts, and its service start/stop/restart — the thing scenario S3 exists to teach — depends
on an init system being present. A one-process-per-container design cannot express "restart
the DataNode" as Ambari means it. Ambari's own documentation describes a Docker environment
built exactly this way (Rocky Linux 8, one server plus agents).

*Cost, stated plainly:* this violates the one-process-per-container convention, requires
elevated privileges, and makes containers heavier. That cost is the price of Ambari being
Ambari. It is accepted deliberately, not overlooked.

**Rejected — supervisord instead of systemd.** Lighter, no privileges needed. But Ambari's
service control scripts invoke `systemctl` directly; shimming every one of them is fragile
and diverges from every piece of upstream documentation.

**Rejected — Vagrant/VirtualBox VMs.** The most faithful reproduction of a real cluster.
Rejected on the user's decision: heavy on a laptop, and VirtualBox has no Apple Silicon
support, which conflicts with the ARM64 requirement.

### D-004 — Agents self-register; SSH bootstrap is not on the happy path

`ambari-agent` is baked into the host image, `/etc/ambari-agent/conf/ambari-agent.ini` points
at the Ambari server's FQDN, and the agent service starts on boot and registers itself.

*Rationale:* Ambari's standard host onboarding SSHes from the server to each host and runs a
bootstrap script that installs the agent. That flow assumes hosts that exist before the
cluster software does. In Docker, the image *already contains* the agent — running an SSH
bootstrap to install what is already installed is pure ceremony, and it drags in a whole
key-distribution problem. Self-registration is the smaller, more reliable mechanism.

SSH is still installed (FR-009) because debugging a seven-host cluster without it is
miserable. It is a debugging affordance, not a dependency.

⚠ **Depends on SPIKE-001** — the exact `ambari-agent.ini` fields and the registration
handshake for Ambari 3.0 have not been verified.

### D-005 — Local package mirror container

An nginx container serves the Ambari and Bigtop RPMs to all hosts; cluster hosts get a
`.repo` file pointing at it.

*Rationale:* three independent wins. **Reproducibility** — the cluster does not break when an
upstream mirror reorganises. **Speed** — seven hosts installing Hadoop pull from localhost,
not the internet. **ARM64** — feature 002's fallback path builds packages locally, and it
needs somewhere to publish them; this is that somewhere.

Ambari's own Docker documentation uses the same pattern (a designated container acting as the
YUM repository host).

### D-006 — Blueprint-driven headless install over REST

The full sequence is specified in `contracts/ambari-rest.md`.

**Rejected — the Ambari Web install wizard.** Violates constitution P2 (no manual steps) and
cannot be tested in CI.

**Rejected — driving the UI with Selenium/Playwright.** Automating a wizard that has a REST
API underneath it is strictly worse than calling the API.

### D-007 — PostgreSQL for both Ambari and Hive, in one container, two databases

*Rationale:* `docker-hive` already uses PostgreSQL for the Hive metastore and ships the full
2.3.0 → txn → 3.0.0 → 3.1.0 schema chain, so the operational knowledge carries over. One
container with two databases keeps the `mini` profile's footprint down.

`POSTGRES_HOST_AUTH_METHOD: trust` — inherited from `docker-hive` — is **not** carried over.
It disables authentication entirely. Generated passwords in `secrets/` instead (P7).

### D-008 — Drop Hue; keep an optional Jupyter edge host

Hue is dropped. It is an unpinned upstream image in the predecessor, it needs its own
configuration surface, and Ambari-managed Zeppelin 0.11.0 covers the same teaching ground
while being part of the stack Ambari manages.

Jupyter is retained as an **optional** `edge1` host, because `docker-hive`'s notebook is a
genuinely good teaching asset and feature 003 reuses it as a parity fixture. It runs as a
client outside the Ambari-managed service set.

### D-009 — Generated artifacts are not committed

Compose files, blueprints, and cluster templates are generated from `cluster-topology.yaml`
and gitignored. Committing them creates two sources of truth and guarantees drift.

*Consequence:* the generator must be runnable before anything else, and its output must be
deterministic (FR-002) so diffs are reviewable when someone dumps them for inspection.

---

## Spikes — must be resolved before dependent work

Each spike names what is unknown, why it matters, how to settle it, and what to do if the
answer is bad. **Constitution P10: do not build on an unresolved spike.**

### SPIKE-001 — Ambari 3.0 agent self-registration (blocks D-004, FR-008)

**Unknown.** The exact contents of `/etc/ambari-agent/conf/ambari-agent.ini` required for
unattended registration against Ambari 3.0.0; whether registration succeeds when the agent
starts before the server's schema is initialised; how the agent determines the hostname it
reports (`hostname -f` vs. a `public_hostname_script` vs. `hostname_script`); and whether
two-way SSL certificate exchange needs any pre-seeding.

**Why it matters.** If self-registration cannot be made reliable, D-004 collapses and the
project must fall back to SSH-based bootstrap — a materially different design touching key
generation, distribution, and the `/api/v1/bootstrap` endpoint.

**How to settle.** Bring up one server container and one agent container by hand. Inspect the
packaged default `ambari-agent.ini`. Observe `GET /api/v1/hosts` and
`/var/log/ambari-agent/ambari-agent.log`. Deliberately start the agent *before* the server and
observe whether it retries or dies.

**If the answer is bad.** Fall back to SSH bootstrap; record the amendment; feature 001 grows
a key-distribution task. Estimated cost: +1 to 2 days.

### SPIKE-002 — Real resource requirements (blocks FR-003, NFR-002)

**Unknown.** Actual RAM, CPU, and disk for each profile. Ambari server alone is commonly
cited around 2 GB; each agent host with HDFS + YARN roles is likely 2–4 GB; the historical
guidance for an Ambari-managed cluster is far above what a laptop offers.

**Why it matters.** If `standard` needs 32 GB, it is not a laptop project and the profile
definitions are wrong. This determines whether `mini` must collapse to a genuine
single-all-in-one-host cluster.

**How to settle.** Build the profiles, run them, measure with `docker stats` under the smoke
suite, and record the peak.

**If the answer is bad.** Redefine `mini` as one host running everything, and document
`standard` as requiring a workstation.

### SPIKE-003 — systemd in Docker under cgroup v2 (blocks FR-006)

**Unknown.** The precise, portable Compose configuration for running systemd as PID 1 across
cgroup v1 hosts, cgroup v2 hosts (Linux 6.x, modern Docker Desktop), and Docker Desktop's
macOS VM. The v1 recipe — bind-mount `/sys/fs/cgroup` read-only, tmpfs on `/run` and
`/run/lock`, `SYS_ADMIN`, `stop_signal: SIGRTMIN+3` — does not transfer unchanged to v2,
where a private cgroup namespace and a writable cgroup mount are involved.

**Why it matters.** This is the foundation. If it is wrong, nothing above it starts, and the
failure mode is an opaque hang rather than a clear error.

**How to settle.** Build one Rocky 8 + systemd image; boot it on a cgroup v1 host, a cgroup
v2 Linux host, and Docker Desktop on macOS; confirm `systemctl is-system-running` reaches
`running` on each. Record the exact working Compose keys per case.

**If the answer is bad.** Fall back to `privileged: true`, documented as a known wart with
its security implications stated.

### SPIKE-004 — Ambari 3.0 REST payload shapes (blocks FR-013, `contracts/ambari-rest.md`)

**Unknown.** The exact request bodies Ambari 3.0.0 expects for repository-version
registration with a BIGTOP stack, and whether the version-definition-file (VDF) flow, the
per-operating-system repository flow, or both are supported. Blueprint and
cluster-creation-template shapes are stable across Ambari's history and are lower risk, but
the stack name and version strings (`BIGTOP` vs `BGTP`, `3.3.0`) are **not** confirmed.

**Why it matters.** A wrong stack identifier fails at the first REST call. Everything
downstream is blocked.

**How to settle.** Stand up the Ambari server alone and introspect: `GET /api/v1/stacks`,
`GET /api/v1/stacks/<name>/versions`, and the resource's own `?fields=*` output. The running
server is the authoritative source; use it rather than any document, this one included.

**If the answer is bad.** Only the contract document changes. Low blast radius, but it gates
everything, so it goes early in `tasks.md`.

### SPIKE-005 — Bigtop 3.3.0 repository layout and OS coverage (blocks FR-010, FR-011)

**Unknown.** The exact repository URLs and directory structure for Ambari 3.0.0 and Bigtop
3.3.0 RPMs, which base OS builds are published (Rocky 8 is expected), whether GPG signing
keys must be imported, and the total mirror size.

**Why it matters.** Determines the mirror-population task and the disk budget. If Rocky 8
builds are not published, D-003's base-image choice changes.

**How to settle.** Fetch the distribution index and enumerate it. Mirror one repository and
measure.

### SPIKE-006 — End-to-end install duration (blocks NFR-001)

**Unknown.** How long a blueprint install of the `standard` profile actually takes with a
warm local mirror. The 45-minute figure in NFR-001 is a placeholder, not a measurement.

**How to settle.** Time three cold runs; set NFR-001 to the median plus 50 %.

### SPIKE-007 — Ambari Metrics viability at this scale

**Unknown.** Whether Ambari Metrics Collector (which embeds an HBase instance) fits inside
the `mini` and `standard` profiles' memory budgets, or whether it must be optional.

**How to settle.** Measure with and without it once SPIKE-002 has a baseline.

**If the answer is bad.** Make Ambari Metrics a `full`-profile-only service and document the
loss of the metrics dashboards in smaller profiles.

---

## Known failure modes to design against

Catalogued now so mitigations are built in, not retrofitted. These belong in the README's
troubleshooting section (FR-026).

| # | Failure | Mitigation |
|---|---|---|
| F1 | Agent registers under a short hostname or container ID instead of its FQDN; blueprint host mapping then does not match | FR-007: set `hostname:` to the FQDN *and* add a network alias; assert `hostname -f` in a preflight check |
| F2 | Agent starts before the server's database is ready and gives up | Bounded retry in the agent's unit; server readiness gate before blueprint submission (FR-014) |
| F3 | Install fails at task 40 of 60 with a generic non-zero exit | FR-015: enumerate failed tasks via REST, print host, component, and stderr tail |
| F4 | `systemctl` inside the container cannot start units — cgroup misconfiguration | SPIKE-003; a preflight assertion that `systemctl is-system-running` is `running` before registration |
| F5 | Time skew between containers breaks Ambari's heartbeat | All hosts share the Docker host clock; assert clock agreement in preflight |
| F6 | Host reports too little memory and Ambari's recommendations produce unusable heap sizes | Pin heap sizes explicitly in blueprint `configurations[]` rather than relying on stack advisor defaults |
| F7 | Repository metadata stale after adding locally-built packages (feature 002) | `createrepo` re-run is part of the mirror task, not a manual step |
| F8 | Ports collide with a concurrently running `docker-hive` | FR-023: distinct host-port map, documented side by side |
| F9 | Cluster left half-installed; `make up` re-run fails on "cluster already exists" | FR-021/P4: detect existing cluster state and resume or report clearly |
| F10 | `/etc/hosts` and Docker DNS disagree after a container restarts with a new IP | Rely on Docker's embedded DNS and network aliases; do not write `/etc/hosts` |

---

## Prior art carried over from `docker-hive`

Read-only. Nothing here creates a dependency (constitution P9).

| Asset | Use |
|---|---|
| `hadoop-hive.env` (~60 `*_CONF_*` vars) | Input to the migration tool (FR-017); source of the tuning table (FR-018) |
| `docker-compose.yml` named-network workaround | Precedent for the FQDN discipline — that comment documents a real `java.net.URISyntaxException` caused by Compose's generated hostnames |
| `hadoop-cluster/base/entrypoint.sh` `wait_for_it()` | Pattern for readiness gating; reimplemented with timeouts and diagnostics per P6 |
| `docker-hive-metastore-postgresql/*.sql` | Documents the Hive 2.3.0 → 3.1.0 schema chain; fallback if Ambari's schema init needs seeding |
| `README.md` port table | Baseline for the new port map, chosen to avoid collisions (F8) |
| `notebooks/work/spark_yarn_test.py`, `map-reduce-example.ipynb` | Parity fixtures for feature 003 |
| `Makefile` buildx targets | Template for multi-arch build targets |

---

## Future features — named, not specified

- **Kerberos** — Ambari automates KDC integration; the natural next lesson after S3.
- **NameNode / ResourceManager HA** — needs ZooKeeper quorum and JournalNodes; a genuine
  multi-master topology, and the strongest argument for this architecture over the
  predecessor's.
- **Rolling upgrade** — Ambari's stack upgrade, the operational skill hardest to teach any
  other way.
- **Ranger authorisation** — Bigtop 3.3.0 ships Ranger 2.4.0 and Ambari supports it.
- **Additional services** — HBase, Kafka, Flink, Phoenix, Alluxio are all in the stack and
  cost only a host-group entry once feature 001 lands.

---

## Amendment log

| Date | Spike / decision | Finding |
|---|---|---|
| 2026-08-27 | — | Initial draft. All spikes open. |
