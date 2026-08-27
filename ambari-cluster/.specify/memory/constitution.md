# Constitution — ambari-bigtop-cluster

**Version 1.0.0** · Ratified 2026-08-27 · Applies to every feature, task, and commit.

These principles are binding. A task that cannot be completed without violating one is not a
task to be completed differently — it is a signal that the principle needs an amendment, which
must be proposed, recorded in this file with a rationale and a date, and version-bumped
before the work proceeds.

---

## P1 — Ambari owns configuration

**No process may write a Hadoop configuration file.** Not a Dockerfile, not an entrypoint,
not a `sed`, not an `envsubst`, not a bind-mounted `core-site.xml`. Every configuration
property enters the cluster through a blueprint `configurations[]` block or through Ambari's
REST configuration API, and Ambari renders it into `/etc/<service>/conf/`.

*Why this is P1:* the predecessor project's entire configuration mechanism is a shell
function that `sed`s `<property>` elements into XML from environment variables, keyed by a
`_`→`.`, `___`→`-`, `__`→`_` encoding. That logic exists in **three drifted copies** across
the repository, two of which have a subtly different substitution order and are therefore
quietly wrong. That is exactly the failure mode Ambari exists to eliminate, and reintroducing
it would defeat the purpose of this project.

**Test:** `grep -rE "sed .*(core|hdfs|yarn|mapred|hive)-site" .` returns nothing.

---

## P2 — The topology is declarative and singular

`cluster-topology.yaml` is the single source of truth for what the cluster *is*: which hosts
exist, which components run where, which services are enabled, how much memory each host gets.

The Docker Compose file, the Ambari blueprint, and the cluster creation template are all
**generated** from it. They are build outputs, not source. Editing a generated file is a bug.

Corollary: **no manual steps.** Nothing in the happy path may require a human to open Ambari
Web and click through the install wizard. A cluster comes up from a cold `make up` with no
interactive input.

**Test:** deleting every generated artifact and re-running the generator reproduces them
byte-for-byte.

---

## P3 — Reproducible, pinned, and self-hosted

Every version — Ambari, Bigtop, the base OS image, PostgreSQL, the JDK, every auxiliary
container — is pinned to an exact version in **one** manifest file. `latest` is forbidden.

The stack's RPMs are served from a **local mirror container**, populated from that manifest.
A cluster build must not depend on an upstream repository being reachable, unchanged, or
still in existence at build time.

*Why:* the predecessor pins Hadoop, Hive, and Spark versions across four separate Dockerfiles
with no central manifest, and pulls `postgres`, `gethue/hue`, and `portainer/portainer` as
unpinned `latest`. Those three images have already drifted underneath it.

**Test:** `grep -rn ":latest\|FROM [a-z/]*$" --include=Dockerfile --include=*.yml .` returns
nothing.

---

## P4 — Idempotent lifecycle

- `make up` on a running cluster converges to the same state; it does not error and does not
  duplicate resources.
- `make up` after a partial failure resumes rather than restarts from zero where Ambari
  permits it.
- `make down` stops everything and preserves data.
- `make destroy` removes everything including volumes, and leaves no orphans.

Every one of these is a tested path, not an aspiration.

---

## P5 — Multi-arch parity is a release gate

`linux/amd64` and `linux/arm64` are both first-class targets. **A feature is not done until
the smoke suite passes on both.**

This is a hard requirement, not a nice-to-have: the predecessor already runs natively on
Apple Silicon, and regressing that is not acceptable. Where upstream does not publish aarch64
packages, this project builds them (see `specs/002-arm64-stack-enablement/`).

An amd64-only merge is permitted only behind an explicitly recorded, time-boxed exception in
`specs/002-arm64-stack-enablement/research.md`.

---

## P6 — Failure must be observable

Every wait, poll, and retry loop has:

1. a **timeout** — no unbounded waits;
2. **progress output** — what it is waiting for, and for how long;
3. a **diagnostic dump on expiry** — the relevant container logs, the failing REST response
   body, the Ambari request task list. Not `exit 1`.

*Why:* the predecessor's readiness gate is `nc -z` in a 100 × 5 s loop that prints a dot and
then gives up silently. Debugging a failed cluster start means reading five containers' logs
by hand. Every minute spent on diagnostics here is repaid the first time an install fails at
step 40 of 60.

**Corollary:** `make logs` and `make diagnose` are first-class targets, not afterthoughts.

---

## P7 — No secrets in version control

Generated SSH keypairs, database passwords, and the Ambari admin password live in
`secrets/`, which is gitignored. They are generated on first `make up`, never committed,
never baked into an image layer, and never printed in full to stdout.

Default credentials for a throwaway local cluster are acceptable **only** if they are
generated per-installation and the README states plainly that this cluster is not
production-safe.

---

## P8 — Test-first

The smoke-test contract (`specs/003-workload-parity-validation/`) is written and agreed
before the provisioning code that must satisfy it. A provisioning feature lands together with
the test that proves it, in the same change.

The minimum bar for "the cluster works" is fixed and non-negotiable:

- HDFS write → read → checksum round-trip
- a YARN MapReduce job reaching `SUCCEEDED`
- a Beeline `CREATE TABLE` / `INSERT` / `SELECT` round-trip against HiveServer2
- a `spark-submit --master yarn` job reaching `SUCCEEDED`
- every Ambari service check passing via REST

---

## P9 — This package is self-contained; the predecessor is prior art, never a dependency

**This specification package must be executable after being copied into a new, empty
repository — with no other project present, and no reference cluster running.** That is its
normal delivery mode, not an edge case.

Concretely:

1. **Every input a task needs is inside this package.** Configuration to migrate, test
   fixtures, port maps, expected outputs — all live under `reference/predecessor/`, copied in
   with attribution and maintained here thereafter.
2. **No task may require the predecessor repository**, whether by path or by instruction. A
   task that says "copy this file from `docker-hive`" is as broken as one containing
   `../docker-hive/` — it just fails later.
3. **No task may require a running predecessor cluster.** Baselines are *computed* from
   committed inputs, not *captured* from a reference deployment. A baseline that cannot be
   reproduced from this package alone is not a baseline.
4. **No file outside this package may be modified** by work on this project.

Prose may freely discuss the predecessor as prior art, cite its files, and quote its bugs —
that is how the design records its reasoning. What is forbidden is a *dependency*.

**Test:** `./check-standalone.sh`, which ships in this package and enforces all five
conditions:

1. every relative path **resolves** inside the package root — a `../../` that stays in the
   tree is fine; what matters is where it lands, not how many segments it has;
2. no executable file (`*.py`, `*.sh`, `*.yaml`, `Makefile`, `Dockerfile`) references the
   predecessor tree;
3. no task instructs the reader to use a live predecessor cluster;
4. every embedded input a spec references actually exists;
5. every internal markdown cross-link resolves.

**And run it after copying**, which is the only way to catch instruction-level dependencies:

```bash
cp -r . /tmp/standalone && cd /tmp/standalone && ./check-standalone.sh
```

A task saying *"copy this file from `docker-hive`"* contains no bad path and passes a naive
grep — it simply fails later, for whoever actually tries to run it. Condition 3 and the
copy-then-check discipline exist for exactly that class of defect.

---

## P10 — Honest uncertainty

A claim that has not been verified is marked as a spike, not written as fact. Specs
distinguish three states explicitly:

- **Decided** (`D-###`) — chosen, with rationale and rejected alternatives recorded.
- **Spike** (`SPIKE-###`) — must be settled by measurement before dependent work starts.
- **Assumed** — believed true, cheap to check, will fail loudly if wrong.

Confidently asserting an unverified detail about an unfamiliar system is the most expensive
mistake available in this project. When a spike resolves, amend the research document with
the finding and the date; do not quietly delete the spike.

---

## Amendment log

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-08-27 | Initial ratification. |
