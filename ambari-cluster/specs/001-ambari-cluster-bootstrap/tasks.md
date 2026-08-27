# Tasks — Feature 001

**This is the implementation entry point.** Tasks are ordered by dependency. `[P]` marks tasks
that may run in parallel with their siblings.

Each task states its **inputs**, **outputs**, **done-condition** (checkable without asking a
human), and the **`FR-###`** it satisfies.

**Rules.**
- Do not start a task whose dependencies are incomplete.
- Do not start Phase 1 until every Phase 0 task is done — Phase 0 resolves spikes the rest of
  the design rests on (constitution P10).
- When a spike resolves, **amend `research.md`** with the finding and the date before
  continuing.
- Commit messages cite the task: `T012: generate blueprint from topology`.

---

## Phase 0 — Foundations (blocking)

### T001 — Repository skeleton
**FR:** — · **Deps:** none
**Do:** Create the layout in `plan.md` § 2. Empty dirs get `.gitkeep`. Add `.gitignore`,
`versions.yaml` (unpopulated), `Makefile` with every target from `contracts/cli.md` stubbed to
`@echo "not implemented"`.
**Done:** `make` lists all targets; `git status` is clean.

### T002 — [P] Host base image · **SPIKE-003 resolved; this task verifies**
**FR:** FR-005, FR-006, FR-006a · **Deps:** T001
**Do:** `images/base/Dockerfile` — `FROM bigtop/puppet:trunk-rockylinux-8`, digest-pinned.
Bake in `upstream-reference.md` § 4 as image layers rather than `docker exec` steps:
`sudo openssh-server openssh-clients which iproute net-tools less vim-enhanced initscripts
wget curl tar unzip git dnf-plugins-core`, `dnf config-manager --set-enabled powertools`,
the Rocky-Devel repo enabled, SELinux disabled, firewalld disabled.
Install **both JDKs**: `java-1.8.0-openjdk-devel` and `java-17-openjdk-devel` (D-010), plus
`python3-distro`.
Compose keys are upstream's: `command: /sbin/init`, `privileged: true`, `mem_swappiness: 0`.
**Done:** on cgroup v1 Linux, cgroup v2 Linux (kernel 6.x), and Docker Desktop macOS,
`docker compose exec base systemctl is-system-running` prints `running` or `degraded` — not
`offline`, not a hang. Both `/usr/lib/jvm/java-1.8.0-openjdk` and
`/usr/lib/jvm/java-17-openjdk` exist. Any deviation from upstream's Compose keys (e.g. adding
`stop_signal: SIGRTMIN+3` for clean shutdown) is recorded in `research.md`.

### T003 — [P] Mirror the package repositories · **SPIKE-005 resolved; this task measures**
**FR:** FR-010, FR-011, FR-011a · **Deps:** T001
**Do:** URLs are confirmed (`upstream-reference.md` § 5) — mirror
`apache-ambari.com/dist/ambari/3.0.0/rocky8/` and `.../bigtop/3.3.0/rocky8/`. Record the
package inventory, per-package architecture tags, and **total mirror size** (still unmeasured).
Fetch `MD5SUMS.txt` from each directory and verify every downloaded file against it (FR-011a);
commit the resulting manifest so a future rebuild is verifiable even if the source disappears
(F13).
**Be considerate:** upstream states the host is bandwidth-limited. Mirror once, cache
aggressively, never re-download in CI.
**Done:** `versions.yaml` populated with real pinned values; mirror size recorded and the disk
budget set from it; every file checksum-verified; the manifest committed.
**Note:** the architecture question is already answered — **x86_64 only**. Feature 002 is on
Path C. Confirm the per-package tags here so T-A01 can size the build precisely.

### T004 — Ambari REST introspection · **resolves SPIKE-004**
**FR:** FR-013 · **Deps:** T002, T003
**Do:** Stand up an Ambari 3.0.0 server container alone. Run every request in
`contracts/ambari-rest.md` § Step 0. Record the exact `stack_name`, `stack_version`,
`operating_systems` identifier for Rocky 8, and which repository-registration flow (VDF vs
direct repository `PUT`) the server accepts.
**Done:** `contracts/ambari-rest.md` amended with verified payloads; `contracts/blueprint.md`
stack strings corrected; SPIKE-004 marked resolved with the date. Raw responses saved under
`docs/api-samples/`.
**Note:** the running server is authoritative. Where it disagrees with the drafted contract,
the server is right and the contract is amended.

### T005 — Sizing baseline · **resolves SPIKE-002, SPIKE-007**
**FR:** FR-003, NFR-002 · **Deps:** T002
**Do:** Measure real RAM/CPU/disk for the Ambari server, one agent host idle, and one agent
host running HDFS + YARN roles. Measure Ambari Metrics Collector separately (SPIKE-007).
Derive honest numbers for `mini`, `standard`, `full`.
**Done:** `plan.md` § 1.2 placeholders replaced with measured figures; NFR-002 confirmed or
amended. If `standard` exceeds a typical laptop, `mini` is redefined as a single all-in-one
host and the README says so plainly.

---

## Phase 1 — Infrastructure

### T006 — [P] Package mirror container
**FR:** FR-010, FR-011, FR-012 · **Deps:** T003
**Do:** `images/repo/` — nginx + `createrepo_c`. `tools/mirror.sh` populates from
`versions.yaml` into gitignored `repo-cache/`, is cached, and re-runs `createrepo` after any
change (failure mode F7).
**Done:** `make mirror` twice downloads nothing the second time; `curl http://repo/…/repodata/repomd.xml`
returns 200; a `yum install` from a test container succeeds with no upstream access.

### T007 — [P] Database container
**FR:** FR-022 · **Deps:** T001
**Do:** PostgreSQL, digest-pinned. Two databases: `ambari`, `hive`. Credentials generated into
`secrets/`. **`POSTGRES_HOST_AUTH_METHOD=trust` is not used** (D-007, P7). Named volume.
**Done:** both databases reachable with generated credentials; `trust` appears nowhere;
data survives container restart.

### T008 — Ambari server image and container
**FR:** FR-013, FR-006a · **Deps:** T002, T006, T007
**Do:** `images/ambari-server/` — base + `python3-psycopg2` + `ambari-server` from the mirror.
Load the schema that ships in the package
(`/var/lib/ambari-server/resources/Ambari-DDL-Postgres-CREATE.sql`) into the `ambari` database,
then run setup non-interactively — the exact upstream invocation
(`upstream-reference.md` § 7), with `--databasehost` pointing at the `ambari-db` container
rather than `localhost`, and secrets from `secrets/`:
```
ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-<pinned>.jar
ambari-server setup -s \
  -j /usr/lib/jvm/java-1.8.0-openjdk \
  --ambari-java-home /usr/lib/jvm/java-17-openjdk \
  --database=postgres --databasehost=ambari-db.ambari.local --databaseport=5432 \
  --databasename=ambari --databaseusername=ambari --databasepassword=<secret>
```
**Watch:** `-j` is the **stack's** JDK (8); `--ambari-java-home` is **Ambari's** (17).
Swapping them is failure mode F12.
**Done:** `GET /api/v1/clusters` returns 200 and `GET /api/v1/stacks` lists the stack. The
default `admin`/`admin` credential is changed to the generated one (P7).

---

## Phase 2 — Hosts and registration

### T009 — Ambari agent image · **SPIKE-001 mostly resolved; verify the edges**
**FR:** FR-008 · **Deps:** T008
**Do:** `images/ambari-agent/` — base + `ambari-agent` from the mirror. The mechanism is
confirmed (`upstream-reference.md` § 8): set `hostname=` in
`/etc/ambari-agent/conf/ambari-agent.ini` to the server's FQDN and start the agent. Enable it
at boot rather than starting it by hand.
Still to verify — these are the failure modes, not the mechanism:
- Does the agent **retry** when started before the server's schema is ready, or exit? (F2)
- Does it report `hostname -f`, or does it need `hostname_script` /
  `public_hostname_script`? This decides whether blueprint host mapping matches. (F1)
- Does two-way SSL certificate exchange need pre-seeding on first registration?
**Done:** one agent container self-registers with no SSH and no manual step;
`GET /api/v1/hosts` lists it; killing and restarting the server does not permanently break the
agent. SPIKE-001 resolved in `research.md`.
**If it fails:** fall back to SSH bootstrap (`/api/v1/bootstrap`), record the amendment, and
add tasks for key generation and distribution.

### T010 — FQDN and network identity
**FR:** FR-007, FR-007a · **Deps:** T009
**Do:** Compose `hostname: <name>` + `domainname: <domain>` (upstream's approach, giving
`hostname -f` = `<name>.<domain>`) plus a matching network alias so Docker DNS resolves it. Add
a preflight assertion, run inside each host before registration, that `hostname -f` equals the
expected FQDN and that every peer FQDN resolves.
**Do NOT** bind-mount a hand-written `/etc/hosts` with hardcoded IPs. Upstream does; its own
Compose file declares no network with the subnet it hardcodes, so the addresses need not match
what Docker assigns, and they change on recreate (F10). Use Docker's embedded DNS.
**Enforce hyphens.** No underscore may appear in any hostname, FQDN label, network name, or the
Compose project name — Compose derives network names from the project name, which is exactly
what produced the predecessor's `java.net.URISyntaxException` (D-011, F11).
**Done:** `GET /api/v1/hosts` reports full FQDNs — never short names or container IDs (F1).
Cross-host `ping <peer-fqdn>` succeeds. `docker network ls` shows no underscore in the
project's network name. The assertion fails loudly when the hostname is deliberately
misconfigured.

### T011 — [P] SSH for debugging
**FR:** FR-009 · **Deps:** T002
**Do:** `sshd` enabled on cluster hosts. Keypair generated at first `make up` into `secrets/`,
public key installed on every host. **Not on the provisioning path.**
**Done:** `make shell HOST=worker1` works; `secrets/` is gitignored; disabling sshd entirely
does not break `make up`.

---

## Phase 3 — Generation

### T012 — [P] Topology schema and validator
**FR:** FR-001, FR-004 · **Deps:** T001
**Do:** `tools/validate.py` implementing rules V1–V10 from `data-model.md`. Every failure names
the offending field and says what to do about it.
**Done:** `make validate` passes on the example topology; ten crafted invalid topologies each
produce their specific, actionable message; exit code 2 on failure.

### T013 — Generator
**FR:** FR-001, FR-002 · **Deps:** T004, T012
**Do:** `tools/generate.py` — topology + `versions.yaml` → `generated/docker-compose.yml`,
`generated/blueprint.json`, `generated/cluster-template.json`. Deterministic: sorted keys, no
timestamps, no host-specific values. Secrets stay as `${SECRET:...}`. Header comment with the
source file and its content hash.
**Done:** run twice → `diff` empty; generated blueprint accepted by
`POST /api/v1/blueprints/`; `grep -r '\${SECRET:' generated/` finds placeholders and
`grep` for any resolved secret finds none.

### T014 — [P] Legacy config migration tool
**FR:** FR-017, FR-018, FR-019 · **Deps:** T012
**Do:** `tools/env2blueprint.py` — read a `hadoop-hive.env`-style file, decode `___`→`-`,
`__`→`_`, `_`→`.` **in that order**, map each prefix (`CORE_CONF`, `HDFS_CONF`, `YARN_CONF`,
`MAPRED_CONF`, `HIVE_SITE_CONF`) to its config type, emit blueprint `configurations[]`.
Write `docs/config-migration.md`: every predecessor setting, carried over or dropped, with the
reason. The dropped list must include `dfs.permissions.enabled=false`,
`hadoop.http.staticuser.user=root`, `POSTGRES_HOST_AUTH_METHOD=trust`,
`dfs.namenode.datanode.registration.ip-hostname-check=false`, and the Hue proxyuser settings
(FR-019).
**Done:** run against `docker-hive`'s `hadoop-hive.env` (copied into `tests/fixtures/`, not
referenced in place — P9); output validates as blueprint `configurations[]`;
`yarn_log___aggregation___enable` correctly becomes `yarn.log-aggregation-enable`; the
migration doc accounts for **every** line of the source file.

---

## Phase 4 — Headless install

### T015 — REST client with bounded gates
**FR:** FR-014 · **Deps:** T004, T010
**Do:** `tools/provision.py` steps 1–2: server readiness and host registration gates. Every
call carries `X-Requested-By`. Every poll has a timeout, progress output, and a diagnostic dump
on expiry (P6). Non-2xx prints the response body.
**Done:** both gates succeed on a healthy cluster; with a host deliberately stopped, the gate
times out and prints which FQDN never registered plus that host's agent log.

### T016 — Repository version registration
**FR:** FR-012 · **Deps:** T006, T015
**Do:** `provision.py` step 3, using whichever flow T004 established. Assert afterwards that
the registered `base_url` is the local mirror.
**Done:** stack version registered pointing at `repo.ambari.local`; the assertion fails if an
upstream URL is registered by mistake.

### T017 — Blueprint submission and cluster creation
**FR:** FR-013 · **Deps:** T013, T016
**Do:** `provision.py` steps 4–5. Handle the pre-existing-blueprint case per
`contracts/ambari-rest.md` — treat identical as success, **never** proceed silently against a
different stored blueprint.
**Done:** `POST` returns 202 with a request id; re-running against an identical existing
blueprint succeeds; re-running against a divergent one fails with a clear message.

### T018 — Install polling and failure reporting
**FR:** FR-015, FR-016 · **Deps:** T017
**Do:** `provision.py` steps 6–7. Progress line per `contracts/cli.md`. On non-`COMPLETED`,
fetch failed tasks and print host, role, command, and stderr tail. Translate `INSTALLED` →
"stopped" in user-facing output. Write `logs/provision-<ts>.jsonl` with secrets redacted.
**Done:** a successful install prints the FR-016 summary; an induced failure (stop a worker
mid-install) prints the failing host and component — **not** a bare stack trace. Verified
against acceptance criterion 9.

---

## Phase 5 — Lifecycle

### T019 — Lifecycle targets
**FR:** FR-020, FR-021, FR-022 · **Deps:** T018
**Do:** `up`, `down`, `destroy`, `status`, `logs`, `shell`, `open`, plus the `contracts/cli.md`
variables and exit codes. `destroy` requires `FORCE=1`.
**Done:** `make up` twice succeeds; `make down && make up` preserves HDFS data;
`make destroy` leaves no containers, volumes, or networks; exit codes 0/1/2/3 correct.

### T020 — [P] Preflight
**FR:** FR-020 · **Deps:** T005, T019
**Do:** `make preflight` — Docker/Compose versions, cgroup version detection (from T002), RAM
and disk against the selected profile, port availability. Run automatically by `up`.
**Done:** passes on a healthy machine; fails with a specific message and exit code 2 when RAM
is short or a port is taken, having changed nothing.

### T021 — [P] Diagnostics
**FR:** FR-015 · **Deps:** T019
**Do:** `make diagnose` producing the tarball described in `contracts/cli.md`, including
per-host `hostname -f`, `systemctl is-system-running`, and clock skew (failure modes F1, F4,
F5). Secrets redacted.
**Done:** the tarball contains every listed artifact; `grep -r <a-known-secret>` over the
extracted tarball finds nothing.

---

## Phase 6 — Verification and documentation

### T022 — Smoke suite
**FR:** FR-024 · **Deps:** T019
**Do:** `tests/smoke/` — the five constitution-P8 checks: HDFS round-trip, YARN MapReduce pi,
Beeline DDL/DML, `spark-submit --master yarn`, Ambari REST service checks. Each reports pass/
fail and duration.
**Done:** `make test` prints 5/5 on a healthy cluster; stopping a service makes the
corresponding check fail rather than hang.

### T023 — [P] CI workflow
**FR:** FR-025 · **Deps:** T022
**Do:** `.github/workflows/nightly-cluster.yml` — scheduled `up` → `test` → `destroy` on
`ubuntu-latest` (amd64). Upload `make diagnose` output on failure.
**Done:** the workflow completes green on a manual dispatch; an induced failure uploads the
diagnostics artifact.

### T024 — [P] Documentation
**FR:** FR-026, FR-027 · **Deps:** T019, T022
**Do:** README from `quickstart.md`; `docs/architecture.md` (the `plan.md` § 1.1 diagram);
`docs/ports.md` including the `docker-hive` collision map (F8); `docs/troubleshooting.md` from
`research.md` § failure modes; a migration section covering what changed from `docker-hive`
and why, **including the Spark 3.5.5 → 3.3.4 regression** (FR-027, D-002).
**Done:** a reader who has never seen the project follows the README to a working cluster
without asking a question. Every F1–F10 failure mode has a troubleshooting entry.

### T025 — Acceptance pass
**FR:** all · **Deps:** T001–T024
**Do:** On a clean machine, walk `quickstart.md` steps 1–9 verbatim and tick every box in its
acceptance checklist. Confirm `spec.md` § 7 criteria 1–9. Confirm every `FR-###` maps to a
completed task and every `SPIKE-###` is resolved or explicitly deferred with an owner.
**Done:** the checklist is complete, with the ARM64 box deferred to feature 002's completion.

---

## Traceability

| FR | Tasks | | FR | Tasks |
|---|---|---|---|---|
| FR-001 | T012, T013 | | FR-015 | T018, T021 |
| FR-002 | T013 | | FR-016 | T018 |
| FR-003 | T005 | | FR-017 | T014 |
| FR-004 | T012 | | FR-018 | T014 |
| FR-005 | T002 | | FR-019 | T014 |
| FR-006 | T002 | | FR-020 | T019, T020 |
| FR-006a | T002, T008 | | FR-011a | T003 |
| FR-007 | T010 | | FR-021 | T019 |
| FR-007a | T010, T012 | | | |
| FR-008 | T009 | | FR-022 | T007, T019 |
| FR-009 | T011 | | FR-023 | T024 |
| FR-010 | T006 | | FR-024 | T022 |
| FR-011 | T006 | | FR-025 | T023 |
| FR-012 | T006, T016 | | FR-026 | T024 |
| FR-013 | T008, T017 | | FR-027 | T024 |
| FR-014 | T015 | | | |

| Spike | Status | Resolved / verified by |
|---|---|---|
| SPIKE-001 agent self-registration | **Mostly resolved** 2026-08-27 (upstream) | T009 verifies retry + hostname reporting |
| SPIKE-002 resource requirements | Open | T005 |
| SPIKE-003 systemd / cgroups | **Resolved** 2026-08-27 (`privileged: true`) | T002 verifies on 3 hosts |
| SPIKE-004 REST payload shapes | **Open** — upstream quick-start stops at the web wizard | T004 |
| SPIKE-005 repository layout | **Resolved** 2026-08-27 (URLs, Rocky 8/9, x86_64 only) | T003 measures mirror size |
| SPIKE-006 install duration | Open | T025 |
| SPIKE-007 Ambari Metrics footprint | Open | T005 |
