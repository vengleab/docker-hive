# Research — Feature 001

Decisions (`D-###`), rejected alternatives, spikes (`SPIKE-###`), and known failure modes.

> **Read this before writing any code.** Several spikes below can invalidate parts of the
> design. Constitution P10 requires that they be settled by measurement, not assumption.
>
> **Update 2026-08-27 — upstream documentation obtained.** The official Ambari quick-start
> pages (Docker environment setup, installation guide, download page) have now been read and
> are transcribed in **`upstream-reference.md`**. `ambari.apache.org` is unreachable from the
> drafting environment, so they were retrieved from the site's own source repository
> (`apache/ambari-website`, branch `main`).
>
> This **resolves SPIKE-003 and SPIKE-005 outright**, substantially resolves **SPIKE-001**,
> and confirms the base-image, JDK, and install-command details. It leaves **SPIKE-002,
> SPIKE-004, SPIKE-006, SPIKE-007** open — those need measurement or a live server.
>
> It also produced the single most consequential finding in this project so far: the official
> download page states that **all packages are built for x86_64 only**, which forces feature
> 002 onto its most expensive path. See `../002-arm64-stack-enablement/research.md`.

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

Every cluster host is a container running `/sbin/init` as PID 1, built from
**`bigtop/puppet:trunk-rockylinux-8`** with **`privileged: true`**.

> **Confirmed against upstream 2026-08-27.** This is exactly what the official Ambari Docker
> environment guide does — same base image, same `command: /sbin/init`, same
> `privileged: true`, plus `mem_limit: 8g` and `mem_swappiness: 0` per container. See
> `upstream-reference.md` § 1. The base image is *not* a bare Rocky 8: it is the Apache Bigtop
> Puppet image, with Java, Puppet, and Hadoop dependencies preinstalled.

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

> **Confirmed against upstream 2026-08-27.** The official installation guide registers agents
> with exactly this mechanism:
> ```bash
> sed -i "s/hostname=.*/hostname=your_ambari_server_hostname/" /etc/ambari-agent/conf/ambari-agent.ini
> ambari-agent start
> ```
> No SSH bootstrap, no wizard host discovery. D-004 is upstream's own path, not a departure
> from it.
>
> The Docker environment guide *does* set up SSH between containers and says it "is required
> for Ambari to function properly" — but its own installation guide then registers agents
> without using it. This project keeps SSH for debugging (FR-009) and does not depend on it.
> See `upstream-reference.md` §§ 3, 8.

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

### D-010 — Two JDKs on every host: Java 17 for Ambari, Java 8 for the stack

*(Added 2026-08-27 from upstream.)* Upstream installs both `java-17-openjdk-devel` and
`java-1.8.0-openjdk-devel` on every host, then passes them separately at setup:

```bash
ambari-server setup -s \
  -j /usr/lib/jvm/java-1.8.0-openjdk \              # the managed stack runs on 8
  --ambari-java-home /usr/lib/jvm/java-17-openjdk   # Ambari itself runs on 17
```

Ambari 3.0.0 added Java 17 support for the server; the Bigtop 3.3.0 stack still runs on Java
8. Both must be present, and the two `-j` / `--ambari-java-home` flags must not be conflated —
getting them backwards is a plausible and confusing failure.

Worth noting against the predecessor: `docker-hive` builds on `openjdk:8-jre` — a **JRE**, not
a JDK. Upstream requires the `-devel` packages. The image build must install JDKs.

### D-011 — Hostnames use hyphens, never underscores

*(Added 2026-08-27.)* Upstream names its containers `bigtop_hostname0`. This project uses
`master1`, `worker1`, `worker2` — hyphens only where a separator is needed.

Underscores are not legal in DNS hostnames (RFC 952 / RFC 1123) and `java.net.URI` rejects
them. **The predecessor has already hit this exact bug**, and left the evidence in
`docker-hive/docker-compose.yml`:

```
# solve java.net.URISyntaxException Illegal character in hostname at index 49:
#   thrift://docker-hive-hive-metastore-1.docker-hive_default:9083
```

The offending character was the underscore in the Compose-generated network name
`docker-hive_default`. On an upstream-named Ambari cluster the Hive metastore URI would be
`thrift://bigtop_hostname0.bigtop.apache.org:9083` — the same exception, in the same
component. Following upstream's naming here would reintroduce a bug this repository already
paid to fix.

Validation rule V7 is extended: expanded FQDNs must match `[a-z0-9]([a-z0-9-]*[a-z0-9])?`
per label. The Compose **project name** must also be hyphenated, since Compose derives network
names from it — that is precisely what bit the predecessor.

### D-009 — Generated artifacts are not committed

Compose files, blueprints, and cluster templates are generated from `cluster-topology.yaml`
and gitignored. Committing them creates two sources of truth and guarantees drift.

*Consequence:* the generator must be runnable before anything else, and its output must be
deterministic (FR-002) so diffs are reviewable when someone dumps them for inspection.

---

## Spikes — must be resolved before dependent work

Each spike names what is unknown, why it matters, how to settle it, and what to do if the
answer is bad. **Constitution P10: do not build on an unresolved spike.**

### SPIKE-001 — Ambari 3.0 agent self-registration · **MOSTLY RESOLVED 2026-08-27**

**Resolved.** Upstream's installation guide sets the `hostname=` field in
`/etc/ambari-agent/conf/ambari-agent.ini` to the Ambari server's hostname and starts the agent
directly — no SSH bootstrap. D-004 stands. See `upstream-reference.md` § 8.

**Still to verify at T009** (cheap, and they are the failure modes, not the mechanism):

- Whether the agent **retries** when it starts before the server's schema is ready, or exits.
  This is failure mode F2 and the likeliest source of flaky cold starts.
- How the agent determines the hostname it *reports* — `hostname -f`, or a `hostname_script` /
  `public_hostname_script` override. This determines whether blueprint host mapping matches
  (failure mode F1).
- Whether two-way SSL certificate exchange needs any pre-seeding on first registration.

**If a fallback is still needed.** SSH bootstrap via `/api/v1/bootstrap`; +1 to 2 days.

### SPIKE-002 — Real resource requirements (blocks FR-003, NFR-002)

**Unknown.** Actual RAM, CPU, and disk for each profile. Ambari server alone is commonly
cited around 2 GB; each agent host with HDFS + YARN roles is likely 2–4 GB; the historical
guidance for an Ambari-managed cluster is far above what a laptop offers.

**Why it matters.** If `standard` needs 32 GB, it is not a laptop project and the profile
definitions are wrong. This determines whether `mini` must collapse to a genuine
single-all-in-one-host cluster.

**Upstream's stated figure (2026-08-27).** The Docker environment guide asks for **≥ 8 GB
free RAM for a 4-node cluster** (1 server + 3 agents), ≥ 20 GB disk. Its Compose file then
sets `mem_limit: 8g` on *each* of the four containers — so the limits sum to 32 GB against a
stated 8 GB requirement. Those are soft caps, not reservations, so both can be true; but the
8 GB figure is for a cluster with **no services installed yet**, and it is optimistic once
HDFS, YARN, Hive, and Ambari Metrics are actually running.

Treat 8 GB as a floor for the `mini` profile, not a prediction for `standard`.

**How to settle.** Build the profiles, run them, measure with `docker stats` under the smoke
suite, and record the peak *after* services are started — not at idle.

**If the answer is bad.** Redefine `mini` as one host running everything, and document
`standard` as requiring a workstation.

### SPIKE-003 — systemd in Docker · **RESOLVED 2026-08-27**

**Resolved.** Upstream's answer is simply `privileged: true` with `command: /sbin/init` on
`bigtop/puppet:trunk-rockylinux-8`. No cgroup bind-mounts, no `tmpfs` on `/run`, no
`stop_signal: SIGRTMIN+3`, no cgroup-version branching. `privileged` sidesteps the cgroup v1
vs v2 distinction entirely, which is why upstream needs no per-host variation.

The elaborate unprivileged recipe this spec previously worried about is not required. The
cost is a blanket privilege grant, which this project **adopts and documents** rather than
hides — see `upstream-reference.md` § Appraisal.

**Remaining work at T002** — verification, not discovery:

- Confirm `systemctl is-system-running` reaches `running`/`degraded` on a cgroup v1 host, a
  cgroup v2 Linux host, and Docker Desktop on macOS.
- Confirm the image's shutdown behaviour; add `stop_signal: SIGRTMIN+3` if `docker compose
  down` is slow or unclean. Upstream omits it; that may be an oversight rather than a finding.
- **Optional later refinement:** narrow `privileged: true` to specific capabilities. Not a
  blocker, and not to be attempted before the privileged path works.

### SPIKE-004 — Ambari 3.0 REST payload shapes (blocks FR-013, `contracts/ambari-rest.md`)

**Unknown.** The exact request bodies Ambari 3.0.0 expects for repository-version
registration with a BIGTOP stack, and whether the version-definition-file (VDF) flow, the
per-operating-system repository flow, or both are supported. Blueprint and
cluster-creation-template shapes are stable across Ambari's history and are lower risk, but
the stack name and version strings (`BIGTOP` vs `BGTP`, `3.3.0`) are **not** confirmed.

**Why it matters.** A wrong stack identifier fails at the first REST call. Everything
downstream is blocked.

**Still open after the 2026-08-27 documentation pass.** Upstream's quick-start path stops at
agent registration and then hands the reader to the **Ambari Web install wizard**. Blueprints
are documented on a separate page and are not covered by the pages transcribed in
`upstream-reference.md`. So the manual runbook is now fully known, but the *headless* path —
which is the whole point of this project (constitution P2) — is not.

**How to settle.** Stand up the Ambari server alone and introspect: `GET /api/v1/stacks`,
`GET /api/v1/stacks/<name>/versions`, and the resource's own `?fields=*` output. The running
server is the authoritative source; use it rather than any document, this one included.

**If the answer is bad.** Only the contract document changes. Low blast radius, but it gates
everything, so it goes early in `tasks.md`.

### SPIKE-005 — Repository layout and OS coverage · **RESOLVED 2026-08-27**

**Resolved** from the official download page (`upstream-reference.md` § 5).

| Artefact | URL |
|---|---|
| Ambari 3.0.0, Rocky 8 | `https://apache-ambari.com/dist/ambari/3.0.0/rocky8/` |
| Ambari 3.0.0, Rocky 9 | `https://apache-ambari.com/dist/ambari/3.0.0/rocky9/` |
| Bigtop 3.3.0, Rocky 8 | `https://apache-ambari.com/dist/bigtop/3.3.0/rocky8/` |
| Bigtop 3.3.0, Rocky 9 | `https://apache-ambari.com/dist/bigtop/3.3.0/rocky9/` |

- **Rocky 8 and Rocky 9 are both published.** Rocky 8 is chosen, matching upstream's Docker
  base image.
- **`gpgcheck=0`** in upstream's own repo file — packages are not GPG-signed. MD5 checksums
  are published as `MD5SUMS.txt` per directory; the mirror task should verify against those,
  since it is the only integrity check available.
- Mirroring is `wget -r -np -nH --cut-dirs=4 --reject 'index.html*'` followed by `createrepo`.
- **Total mirror size is still unmeasured** — measure at T006 and set the disk budget from it.

**Two findings that raise the stakes on D-005 (the local mirror):**

1. **The host is `apache-ambari.com`, not an `apache.org` domain.** It is a community-run
   distribution site, not ASF infrastructure.
2. The page states: *"This site is hosted on a server with limited bandwidth. Please be
   considerate when downloading packages."*

A community-run, bandwidth-constrained, unsigned, single-source distribution point is a
genuine single point of failure for this project. The local mirror was already decided (D-005)
for reproducibility and speed; it is now also a matter of **not hammering a volunteer-funded
server**, and of surviving that server's eventual disappearance. **FR-012 (a full rebuild with
upstream unreachable) is the requirement that matters most in this whole spec**, and it should
be treated as such rather than as a nice-to-have. Consider committing the mirror manifest with
per-file checksums so a future rebuild can be validated even if the source is gone.

> ### ⚠ **"All packages are built for x86_64 architecture."**
>
> Stated plainly on the same page. There are **no aarch64 packages**. This resolves
> SPIKE-A01 to its worst case and is the dominant finding for feature 002 — see
> `../002-arm64-stack-enablement/research.md`.

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
| F10 | `/etc/hosts` and Docker DNS disagree after a container restarts with a new IP | Rely on Docker's embedded DNS and network aliases; do not write `/etc/hosts`. **Upstream does the opposite** — it bind-mounts a hosts file with hardcoded `172.20.0.2`–`.5` addresses while declaring no network with that subnet, so its addresses need not match what Docker assigns. Rejected deliberately; see `upstream-reference.md` § Appraisal |
| F11 | An underscore in a hostname, network name, or Compose project name produces `java.net.URISyntaxException` in Hive's metastore URI | D-011: hyphens only; validation rule V7 enforces DNS-label syntax on every generated FQDN and on the Compose project name |
| F12 | `-j` and `--ambari-java-home` swapped at `ambari-server setup`, pointing Ambari at Java 8 and the stack at Java 17 | D-010: both flags set explicitly from one place; assert both JDK paths exist during preflight |
| F13 | The community-run `apache-ambari.com` distribution point is slow, rate-limited, or gone | D-005 mirror; FR-012 offline rebuild; commit the mirror manifest with checksums so a rebuild is verifiable even if the source disappears |

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
| 2026-08-27 | SPIKE-003 | **Resolved.** Upstream uses `privileged: true` + `command: /sbin/init` on `bigtop/puppet:trunk-rockylinux-8`. No cgroup-version branching needed. |
| 2026-08-27 | SPIKE-005 | **Resolved.** Repo URLs confirmed on `apache-ambari.com`; Rocky 8 and 9 published; `gpgcheck=0`, MD5SUMS only; mirror size still to measure. |
| 2026-08-27 | SPIKE-001 | **Mostly resolved.** `ambari-agent.ini` `hostname=` + `ambari-agent start` is upstream's own mechanism. Retry-before-server-ready and hostname-reporting behaviour still to verify at T009. |
| 2026-08-27 | SPIKE-002 | Upstream states ≥ 8 GB for a 4-node cluster *before* services are installed. Treated as a floor for `mini`, not a prediction for `standard`. Still to measure. |
| 2026-08-27 | SPIKE-004 | Still open. Upstream's quick-start ends at the Ambari Web wizard; blueprints are not covered by those pages. |
| 2026-08-27 | D-003 | Amended: base image is `bigtop/puppet:trunk-rockylinux-8`, not bare Rocky 8. |
| 2026-08-27 | D-010 | Added: dual JDK — Java 17 for the Ambari server, Java 8 for the managed stack. |
| 2026-08-27 | D-011 | Added: hyphens-only hostnames. Upstream's `bigtop_hostname0` would reintroduce the `URISyntaxException` the predecessor already fixed. |
| 2026-08-27 | F10–F13 | Failure modes added from the upstream review. |
