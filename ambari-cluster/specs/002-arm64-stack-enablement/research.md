# Research — Feature 002 (ARM64)

> **Everything here is provisional.** The drafting environment had restricted network egress;
> Bigtop's distribution mirrors could **not** be enumerated directly. Every statement about
> what is or is not published is a hypothesis to be tested by feature 001's **T003**.
> Constitution P10 applies.

---

## What is actually known

**Confirmed.**
- Apache Bigtop has carried ARM64/AArch64 support work across several release cycles; it is a
  recognised target for the project, not an afterthought.
- Apache Hadoop publishes an official aarch64 **tarball** (`hadoop-3.3.6-aarch64.tar.gz`).
  This is precisely how `docker-hive` obtains ARM support — see its
  `hadoop-cluster/base/Dockerfile`, which branches on `TARGETARCH`.
- Bigtop 3.3.0 added Rocky Linux 8 as a supported OS.
- Ambari 3.0.0 targets the Bigtop 3.3.0 stack.

**Not confirmed — this is the gap.**
- Whether the published Bigtop 3.3.0 **RPM repositories** include an `aarch64` tree.
- Whether that tree, if it exists, covers every component this project installs, or only a
  subset.
- Whether `ambari-server` and `ambari-agent` packages are architecture-independent or
  architecture-specific. Both are largely Java and Python, which *suggests* they are portable,
  but packaging metadata may still declare an architecture.
- Whether native libraries (Hadoop native, Snappy, LZO) are built for aarch64 in those
  packages. This matters concretely: `docker-hive` sets
  `io.compression.codecs=org.apache.hadoop.io.compress.SnappyCodec` and
  `mapreduce.map.output.compress=true`, so Snappy is on the hot path, not a corner case.

**The distinction that matters.** "Bigtop supports ARM64" and "the Bigtop 3.3.0 release
publishes aarch64 RPMs for Rocky 8" are different claims. The first is well supported. The
second is what this feature depends on, and it is the one that has not been verified.

---

## SPIKE-A01 — aarch64 package availability

**Resolved by:** feature 001, T003. **Blocks:** everything in this feature.

### Method

1. Enumerate the Bigtop 3.3.0 distribution tree. For each supported OS, list the architecture
   subdirectories present.
2. For the Rocky 8 tree, list every package and its architecture tag. Distinguish `noarch`
   from `x86_64` from `aarch64`.
3. Cross-check against the component list this project installs: Hadoop (HDFS, YARN,
   MapReduce), Hive, ZooKeeper, Tez, Ambari Metrics, plus `bigtop-utils`, `bigtop-jsvc`,
   `bigtop-groovy`, `bigtop-select`.
4. Separately check the Ambari 3.0.0 packages' architecture tags.
5. On an ARM64 machine, attempt `yum install` of one core package from a mirrored aarch64
   repository. Installing is the real test; a directory listing is only evidence.

### Record the answer as

| Component | `noarch` | `x86_64` | `aarch64` | Notes |
|---|---|---|---|---|
| ambari-server | | | | |
| ambari-agent | | | | |
| hadoop / hadoop-hdfs / hadoop-yarn / hadoop-mapreduce | | | | native libs? |
| hive / hive-metastore / hive-server2 | | | | |
| zookeeper | | | | |
| tez | | | | |
| ambari-metrics-* | | | | embeds HBase |
| bigtop-utils / -jsvc / -groovy / -select | | | | |
| snappy / lzo native | | | | see note above |

Then set the path (A, B, or C) and amend this document with the date and the finding.

---

## Path A — packages exist

The easy case. Work is ordinary multi-arch plumbing.

- `tools/mirror.sh` gains architecture awareness (FR-A08), keyed off the build platform.
- Image builds use `docker buildx --platform linux/amd64,linux/arm64`, following the pattern
  already in `docker-hive`'s Makefile.
- The base image's package installs resolve per-architecture automatically once the repository
  is right.
- The smoke and parity suites run on both platforms in CI.

**Estimate:** 2–3 days. **Main risk:** silent fallback — the mirror fetching `x86_64` packages
on an ARM build and failing at install time with a confusing error. FR-A08 exists to make that
loud.

---

## Path C — no packages, build from source

The expensive case. Documented here so its cost is visible before it is chosen.

### What Bigtop's build actually is

Apache Bigtop builds its packages with a Gradle-driven toolchain. In outline:

- A **toolchain** step installs build dependencies (JDK, Maven, Gradle, protobuf, cmake,
  native toolchains) — Bigtop provides Puppet manifests and container images for this.
- **Per-component build tasks** fetch each component's source at the version pinned in the
  release's BOM, patch it, build it, and package it as an RPM or DEB.
- Bigtop ships **build container images** per target OS, so builds run in a controlled
  environment rather than on the developer's machine directly.

The exact task names and container image tags for Bigtop 3.3.0 must be read from that release's
own documentation and `build.gradle` — **do not guess them.** This is a spike in its own right
(SPIKE-A02 below).

### SPIKE-A02 — Bigtop build toolchain on ARM64

**Unknown.** Whether Bigtop's build container images are published for aarch64; whether the
build tasks run natively on an ARM64 host; whether cross-compilation from amd64 is supported
or whether an ARM64 build host is required.

**Why it matters.** If the toolchain itself is amd64-only, Path C needs an ARM64 build machine
or a cross-compilation strategy — a different project shape and possibly a hardware
requirement.

**How to settle.** Clone Bigtop at the 3.3.0 tag on an ARM64 machine, run the toolchain step,
and build one small component end to end. `bigtop-utils` or `zookeeper` is a reasonable first
target — small, few native dependencies.

### SPIKE-A03 — native library coverage

**Unknown.** Whether Hadoop's native libraries, Snappy, and LZO build cleanly for aarch64
within Bigtop's build, and whether their absence would be a hard failure or a silent
performance loss.

**Why it matters.** `docker-hive` enables Snappy compression for MapReduce output. If the
native codec is missing on ARM, jobs either fail or silently fall back — and the second is
worse, because it looks like it works.

**How to settle.** After a build, run `hadoop checknative -a` on an ARM host and record the
result. Include it in the feature-003 parity suite so a regression is caught.

### Practical costs to plan for

- **Time:** building a full Hadoop-ecosystem stack is measured in hours per full run, not
  minutes. NFR-A02 sets a 12-hour ceiling and requires resumability.
- **Disk:** source trees, Maven and Gradle caches, and output packages. Budget generously.
- **Iteration pain:** a single failing component late in a long build is the normal case.
  Per-component caching (NFR-A03) is what makes this survivable, not a nicety.

### Publishing

Built RPMs land in the feature-001 mirror (`repo` container) with `createrepo` metadata
regenerated automatically (FR-A10, failure mode F7). The mirror already exists precisely so
this path has somewhere to publish to — that was one of the three reasons for decision D-005.

---

## Path B — partial

Mechanically Path A for what exists plus Path C for the gap. The main hazard is *mixing*: a
repository containing both mirrored and locally built packages must have consistent metadata
and non-conflicting versions. Keep the two in separate repository directories with distinct
names so provenance stays legible, and let yum resolve across both.

---

## Fallback if ARM64 proves infeasible

Constitution P5 permits an amd64-only merge **only** behind an explicitly recorded, time-boxed
exception here. If it comes to that, the exception must record:

- the date, the reason, and the owner;
- the review date;
- the interim user guidance — Apple Silicon users run under Docker Desktop's emulation, with
  the measured performance cost stated honestly (NFR-A01's benchmark serves this purpose too);
- what would unblock native support.

An exception is not the same as dropping the requirement. `docker-hive` runs natively on ARM
today; a successor that quietly does not is a regression its users will notice.

---

## Amendment log

| Date | Spike | Finding |
|---|---|---|
| 2026-08-27 | — | Initial draft. SPIKE-A01, A02, A03 all open. Path undetermined. |
