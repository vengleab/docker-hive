# Tasks — Feature 002 (ARM64)

**Gate:** do not start T-A02 or later until **T-A01** has reported and the path (A, B, or C) is
recorded in `research.md`. Constitution P10.

---

## Phase A0 — Determine the path (blocking)

### T-A01 — Package availability survey · **resolves SPIKE-A01**
**FR:** — · **Deps:** feature 001 T003
**Do:** Execute the method in `research.md` § SPIKE-A01. Fill in the component/architecture
table. Attempt an actual `yum install` of one core package from a mirrored aarch64 repository
on an ARM64 machine — a directory listing is evidence, an install is proof.
**Done:** the table is complete; the path (A / B / C) is declared in `research.md` with the
date; if the path is **C**, the effort estimate is confirmed with the project owner **before**
any further work starts.

---

## Phase A1 — Multi-arch plumbing (all paths)

### T-A02 — Architecture-aware mirror
**FR:** FR-A02, FR-A08 · **Deps:** T-A01, feature 001 T006
**Do:** Extend `tools/mirror.sh` to fetch packages for the target architecture. **Fail loudly**
if the requested architecture is unavailable — never silently fall back to `x86_64`, which
would fail at install time with an unrelated-looking error.
**Done:** mirroring for `aarch64` populates aarch64 packages; requesting an unavailable
architecture exits non-zero with a message naming the architecture and the components missing.

### T-A03 — [P] Multi-arch image builds
**FR:** FR-A01 · **Deps:** T-A01, feature 001 T002
**Do:** `make build-multiarch` using `docker buildx --platform linux/amd64,linux/arm64` for
base, ambari-server, ambari-agent, and repo images. Follow the pattern already established in
`docker-hive`'s Makefile — and, unlike it, include **every** image in the aggregate target.
*(Its `buildx` target omits `buildx-hive`, `buildx-hive-metastore-postgresql`, and
`buildx-spark-notebook`. Do not repeat that.)*
**Done:** `docker buildx imagetools inspect` shows both platforms for every image; the
aggregate target covers all four with none omitted.

### T-A04 — Architecture assertion
**FR:** FR-A04 · **Deps:** T-A03
**Do:** Add an assertion to `provision.py`'s host-registration gate: on an ARM64 build, every
host must report `Hosts/os_arch == aarch64`. Surface `os_arch` in `make status`.
**Done:** the assertion passes on a native ARM64 cluster and fails on an emulated one — this
is the machine-checkable difference between "works" and "works natively".

---

## Phase A2 — Build from source (paths B and C only)

*Skip this entire phase on Path A.*

### T-A05 — Bigtop toolchain spike · **resolves SPIKE-A02**
**FR:** FR-A09 · **Deps:** T-A01
**Do:** Clone Apache Bigtop at the 3.3.0 tag on an ARM64 machine. Read that release's own
build documentation and `build.gradle` for the real task names and container image tags —
**do not guess them.** Run the toolchain step. Build one small component end to end
(`bigtop-utils` or `zookeeper`).
**Done:** one aarch64 RPM is produced and installs on Rocky 8 ARM64. `research.md` records the
exact commands, whether the build runs natively or needs an amd64 host, and the wall-clock
time. SPIKE-A02 resolved.

### T-A06 — Build pipeline
**FR:** FR-A09, FR-A11, FR-A12 · **Deps:** T-A05
**Do:** `tools/build-packages.sh` — build the identified missing components for aarch64.
Per-component caching (NFR-A03), resumable after interruption (NFR-A02), and a manifest
recording per component: Bigtop version, source commit, build host architecture, build date
(FR-A12).
**Done:** a full build completes within the NFR-A02 ceiling; killing and re-running resumes
rather than restarting; the manifest is complete for every built package.

### T-A07 — Publish into the mirror
**FR:** FR-A10 · **Deps:** T-A06, feature 001 T006
**Do:** Publish built RPMs into the `repo` container, with `createrepo` metadata regenerated
as part of the step, never manually (failure mode F7). Keep mirrored and locally built
packages in **separate repository directories** with distinct names so provenance stays legible
(Path B mixing hazard).
**Done:** an ARM64 host installs from the local repository with no upstream access; `yum info`
shows the correct repository per package; metadata is current immediately after publishing.

### T-A08 — [P] Native library verification · **resolves SPIKE-A03**
**FR:** FR-A13 · **Deps:** T-A07
**Do:** Run `hadoop checknative -a` on an ARM64 cluster host. Record which native libraries are
present, especially **Snappy** — `docker-hive` enables Snappy for MapReduce output, so it is on
the hot path, and a silent fallback is worse than a hard failure because it looks like success.
Add the check to the parity suite so a regression is caught.
**Done:** the result is recorded in the support matrix; any missing library is either fixed or
documented as unsupported with its consequence stated (FR-A13); the check runs in feature 003's
suite.

---

## Phase A3 — Verification and documentation

### T-A09 — ARM64 smoke and parity
**FR:** FR-A05, FR-A06 · **Deps:** T-A04, (T-A07 on paths B/C)
**Do:** Run feature 001's `make test` and feature 003's parity suite on a native ARM64 machine.
**Done:** both suites pass 100 % on `linux/arm64` with no test skipped or marked expected-fail.

### T-A10 — [P] Performance benchmark
**FR:** NFR-A01 · **Deps:** T-A09
**Do:** On the same ARM64 machine, run an identical workload natively and under amd64
emulation. Record wall-clock for cluster start and for the MapReduce pi job.
**Done:** the comparison is published in the docs with real numbers — this is the concrete
answer to "why does native ARM matter".

### T-A11 — [P] Support matrix and documentation
**FR:** FR-A07, FR-A13 · **Deps:** T-A08, T-A09
**Do:** Publish `docs/architecture-support.md`: per component, whether it is natively packaged
upstream, built locally by this project, or unsupported on aarch64 — with reasons. Document the
build pipeline (paths B/C) well enough that a reader reproduces it from the document alone.
**Done:** the matrix is complete and accurate; a reader on a clean ARM64 machine follows the
document to a working build without asking a question.

### T-A12 — CI on ARM64
**FR:** FR-A01, FR-A05 · **Deps:** T-A09
**Do:** Extend the nightly workflow with an `arm64` runner job. If no ARM64 runner is
available, document the manual verification procedure and its cadence rather than pretending
CI covers it.
**Done:** either the ARM64 job runs green, or the manual procedure is documented with an owner
and a cadence. Silence on this point is not acceptable — P5 is a release gate.

---

## Traceability

| FR | Tasks | | FR | Tasks |
|---|---|---|---|---|
| FR-A01 | T-A03, T-A12 | | FR-A08 | T-A02 |
| FR-A02 | T-A02 | | FR-A09 | T-A05, T-A06 |
| FR-A03 | T-A02, T-A03 | | FR-A10 | T-A07 |
| FR-A04 | T-A04 | | FR-A11 | T-A06 |
| FR-A05 | T-A09, T-A12 | | FR-A12 | T-A06 |
| FR-A06 | T-A09 | | FR-A13 | T-A08, T-A11 |
| FR-A07 | T-A11 | | NFR-A01 | T-A10 |

| Spike | Resolved by |
|---|---|
| SPIKE-A01 package availability | T-A01 |
| SPIKE-A02 Bigtop toolchain on ARM | T-A05 |
| SPIKE-A03 native library coverage | T-A08 |
