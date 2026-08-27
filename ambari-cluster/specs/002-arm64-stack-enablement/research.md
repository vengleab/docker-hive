# Research — Feature 002 (ARM64)

> # ⚠ SPIKE-A01 IS RESOLVED — and the answer is **Path C**
>
> **2026-08-27.** The official Apache Ambari download page states, verbatim:
>
> > **“All packages are built for x86_64 architecture.”**
>
> There are **no aarch64 packages** for Ambari 3.0.0 or the Bigtop 3.3.0 stack at the
> published distribution point. The page lists Rocky 8 and Rocky 9 builds only, and this is
> the single sentence covering architecture. Source transcribed in
> `../001-ambari-cluster-bootstrap/upstream-reference.md` § 5.
>
> **Consequence:** native ARM64 requires **building the entire Bigtop 3.3.0 stack from
> source**. That is Path C below — the most expensive branch, estimated at 3–6 weeks.
>
> **This is a decision point for the project owner, not a task to absorb silently.** Feature
> 002's `spec.md` § 8 requires the scope be confirmed before Path C work begins. Constitution
> P5 makes ARM64 a release gate; P5 also provides the time-boxed exception mechanism if the
> owner decides the cost is not worth paying. Either answer is legitimate. Proceeding without
> an answer is not.

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

**Now confirmed (2026-08-27).**
- The published Ambari 3.0.0 and Bigtop 3.3.0 repositories are **x86_64 only**. No aarch64
  tree exists at `apache-ambari.com/dist/`.
- Upstream's own Docker base image, `bigtop/puppet:trunk-rockylinux-8`, would additionally
  need an aarch64 variant. Whether one is published is **still unverified** and is now the
  first thing T-A01 should check — if it is not, even the *host image* has to be built before
  any package work begins.

**Still unverified, and now more important than before.**
- Whether `ambari-server` / `ambari-agent` RPMs are genuinely architecture-specific or merely
  tagged `x86_64` while containing only Java and Python. If they are effectively portable,
  they may be rebuildable or repackaged cheaply, and only the *stack* needs a real build. This
  is the single highest-leverage question in this feature — **check it first**, because it can
  cut the work substantially.
- Whether native libraries (Hadoop native, Snappy, LZO) build cleanly for aarch64. This
  matters concretely: `docker-hive` sets
  `io.compression.codecs=org.apache.hadoop.io.compress.SnappyCodec` and
  `mapreduce.map.output.compress=true`, so Snappy is on the hot path, not a corner case.

**The distinction that mattered.** "Bigtop supports ARM64" and "the Bigtop 3.3.0 release
publishes aarch64 RPMs for Rocky 8" are different claims. The first is well supported — Bigtop
has carried AArch64 work for several release cycles. The second is what this feature depended
on, and it is now confirmed **false** for the distribution point Ambari 3.0.0 points at.

That gap is the whole of feature 002: the *source* supports ARM; the *published binaries* do
not.

---

## SPIKE-A01 — aarch64 package availability · **RESOLVED 2026-08-27 → Path C**

**Answer:** no aarch64 packages are published. See the banner at the top of this file.

T-A01 is therefore no longer a discovery task but a **confirmation and scoping** task. Its
remaining job is to establish precisely how much must be built, which is what decides whether
Path C is three weeks or six. Run the method below with that framing, and check the two
highest-leverage questions first:

1. **Is there an aarch64 `bigtop/puppet:trunk-rockylinux-8`?** If not, the host image itself
   must be built before any package work starts.
2. **Are `ambari-server` / `ambari-agent` genuinely architecture-specific?** They are largely
   Java and Python. If they only carry an `x86_64` tag without real native content, they may
   be rebuildable cheaply — leaving only the stack to build, which is a materially smaller
   job.

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

## Path A — packages exist · **RULED OUT 2026-08-27**

Retained for the record. This was the hoped-for case; the download page rules it out.

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

## Path C — no packages, build from source · **THIS IS THE CONFIRMED PATH**

The expensive case, and the one that applies. Documented here so its cost is visible before it
is chosen — and it must be *chosen*, explicitly, by the project owner (`spec.md` § 8).

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

## Path B — partial · **RULED OUT for the stack**

Retained for the record, and still partially relevant: if T-A01 finds that `ambari-server` and
`ambari-agent` are effectively architecture-neutral, the *management layer* behaves like Path A
while the *stack* is Path C. That is the best realistic outcome.

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
| 2026-08-27 | **SPIKE-A01** | **RESOLVED → Path C.** The official Ambari download page states "All packages are built for x86_64 architecture." No aarch64 packages exist. Native ARM64 requires building the Bigtop 3.3.0 stack from source. Scope confirmation with the project owner is required before Path C work begins. |
| 2026-08-27 | SPIKE-A02 | Still open, and now on the critical path rather than contingent. Additionally: whether an aarch64 `bigtop/puppet:trunk-rockylinux-8` base image exists is now part of this spike. |
| 2026-08-27 | SPIKE-A03 | Still open. |
