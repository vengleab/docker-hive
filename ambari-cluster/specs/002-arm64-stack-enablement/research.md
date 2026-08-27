# Research — Feature 002 (ARM64)

> # SPIKE-A01 — resolved, then substantially revised
>
> ## ⚠ Read this correction before planning
>
> **First finding (2026-08-27).** The official Apache Ambari download page states, verbatim:
>
> > **“All packages are built for x86_64 architecture.”**
>
> So there are no aarch64 packages **at the Ambari distribution point**
> (`apache-ambari.com`). Transcribed in
> `../001-ambari-cluster-bootstrap/upstream-reference.md` § 5.
>
> **Correction, same day.** That sentence was initially read as "Bigtop is x86_64 only" and
> the feature was put on Path C at 3–6 weeks. **That reading was wrong, and the estimate with
> it.** Apache Bigtop supports AArch64 and has for several release cycles. The limitation
> belongs to the Ambari *distribution site*, not to Bigtop.
>
> Verified directly against Docker Hub's registry API:
>
> ```
> bigtop/puppet:3.3.0-rockylinux-8-aarch64      ✔ exists
> bigtop/slaves:3.3.0-rockylinux-8-aarch64      ✔ exists
> bigtop/puppet:trunk-rockylinux-8-aarch64      ✔ exists
> ```
>
> `bigtop/puppet:…-rockylinux-8-aarch64` is **the aarch64 variant of the exact base image
> Ambari's own Docker guide uses**, and `bigtop/slaves:…-rockylinux-8-aarch64` is the
> matching *build* environment — meaning Bigtop's CI compiles this stack on aarch64 as a
> routine, exercised path.
>
> Bigtop's own repository definitions are architecture-parameterised by design:
> ```ini
> baseurl=http://repos.bigtop.apache.org/releases/3.3.0/rockylinux/8/$basearch
> ```
> (from `archive.apache.org/dist/bigtop/bigtop-3.3.0/repos/rockylinux-8/bigtop.repo`)
>
> **What this changes.** Two of the three things that made Path C expensive are already
> solved upstream: the ARM host image exists, and the ARM build toolchain exists and is CI-
> exercised. The remaining question is narrow and cheap to answer — see SPIKE-A04, now the
> single highest-value check in this feature. **Do not commit to a 3–6 week source build
> before running it.**
>
> The scope decision (T-A00) still belongs to the project owner, but it should be taken
> against SPIKE-A04's answer, not against the superseded estimate.

---

## Why is ARM a problem at all? — the underlying reasons

Worth understanding, because it explains which parts of this are genuinely hard and which are
merely someone's build capacity.

**Java itself is not the problem.** The JVM runs on AArch64, and a `.jar` is architecture-
neutral. If the Hadoop ecosystem were pure Java, ARM support would be free.

**Native code is the problem.** The stack carries a substantial amount of compiled C/C++
reached through JNI, and every piece of it must be built per-architecture:

| Native component | Where it bites |
|---|---|
| `libhadoop.so` — Hadoop native library | Compression codecs, raw erasure coding, `NativeIO`. Missing → silent fallback to slower Java paths |
| **Snappy** (`libsnappy`, `snappy-java`) | Directly relevant here: `docker-hive` sets `io.compression.codecs` to SnappyCodec and enables map-output compression |
| LZO, zstd, ISA-L | Optional codecs, same story |
| `leveldbjni` / RocksDB JNI | YARN NodeManager recovery state store, timeline service |
| protobuf `protoc` | Build-time. Some releases historically shipped an x86-only prebuilt binary inside the artifact |

Several of these historically shipped **prebuilt x86 binaries bundled inside Maven artifacts**,
so a naive ARM build picks up an x86 `.so`, links, and then fails at runtime — or, worse,
degrades quietly. Apache Bigtop's ARM work over recent releases has largely been the patient
job of finding and fixing exactly these, component by component. It is real engineering, and
it is not finished everywhere: e.g. `BIGTOP-3677` records HBase failing to build on arm64 and
ppc64le for CentOS 7 due to missing libraries.

**And then there is capacity.** Supporting a second architecture doubles the build and smoke-
test matrix. For a volunteer-run project that is a genuine cost, and it is the reason ARM
coverage varies by component, by OS, and by release rather than being uniformly present.

### Which of these applies to *this* project

The Ambari distribution site's x86_64-only stance is **capacity**, not capability — it is one
community-run build host, not a statement about the software. Bigtop's own ARM support is
real. What remains genuinely uncertain is only whether the aarch64 *binaries* were published
somewhere reachable (SPIKE-A04), and whether the native libraries in a given build are
complete and correct (SPIKE-A03 — which is why `hadoop checknative -a` is a required check,
not a nicety).

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

## SPIKE-A04 — Does Bigtop publish aarch64 RPMs of its own? · **OPEN — check this first**

**The highest-leverage unanswered question in this feature.** Its answer swings the estimate
between roughly a week and roughly a month.

Ambari's distribution site is x86_64-only. But Ambari 3.0.0 manages the **Bigtop 3.3.0**
stack, and Bigtop is a separate project with its own release infrastructure, its own
repositories, and confirmed ARM build environments. If Bigtop publishes aarch64 RPMs at its
own repository, the stack does not need building at all — the mirror simply points at Bigtop
for the stack packages instead of at `apache-ambari.com`.

**What to check.**

```bash
# Bigtop's own repo, architecture-parameterised:
http://repos.bigtop.apache.org/releases/3.3.0/rockylinux/8/aarch64/repodata/repomd.xml
http://repos.bigtop.apache.org/releases/3.3.0/rockylinux/8/x86_64/repodata/repomd.xml
```

If `aarch64/` resolves with real `repodata`, enumerate the packages and compare against the
component list this project installs.

> **Not verifiable from the drafting environment.** `repos.bigtop.apache.org` is blocked by
> the egress proxy — every architecture returned an identical `403 CONNECT tunnel failed`,
> which is the proxy speaking, not the server. **A uniform 403 across all three architectures
> is evidence of nothing.** Run this from an unrestricted network.

**Outcomes.**

| If | Then | Rough cost |
|---|---|---|
| Bigtop publishes complete aarch64 RPMs | Point the mirror at Bigtop for the stack. Only Ambari's own `ambari-server`/`ambari-agent` need attention (see SPIKE-A01 below — they may be portable). | **~1 week** |
| Bigtop publishes partial aarch64 | Mirror what exists, build the gap with `bigtop/slaves:3.3.0-rockylinux-8-aarch64` | 1–3 weeks |
| Bigtop publishes none | Build the stack with Bigtop's own ARM slave image — still far cheaper than assumed, since the toolchain is CI-exercised rather than experimental | 3–6 weeks |

**Also check:** Bigtop 3.4.0, 3.5.0, and 3.6.0 exist. Their ARM images target
`rockylinux-9-aarch64` rather than Rocky 8 — so if a newer stack ever becomes an option,
Rocky 9 is the ARM-supported base. Not actionable now (Ambari 3.0.0 targets Bigtop 3.3.0),
but worth knowing before anyone pins Rocky 8 as immovable.

---

## SPIKE-A01 — aarch64 packages at the *Ambari* distribution point · **RESOLVED 2026-08-27**

**Answer:** `apache-ambari.com` publishes no aarch64 packages. This is a fact about *that
site*, not about Bigtop — see the correction at the top of this file.

Of the two questions this spike originally raised:

1. ~~**Is there an aarch64 `bigtop/puppet:…-rockylinux-8`?**~~ — **ANSWERED: yes.**
   `bigtop/puppet:3.3.0-rockylinux-8-aarch64` and `trunk-rockylinux-8-aarch64` both exist on
   Docker Hub. The host image does **not** need building.
2. **Are `ambari-server` / `ambari-agent` genuinely architecture-specific?** — still open, and
   now second only to SPIKE-A04 in value. Both are largely Java and Python. If their `x86_64`
   tag is packaging metadata rather than real native content, they may be rebuildable cheaply
   or even installable with `--ignorearch`. Check `rpm -qp --qf '%{ARCH}\n'` and inspect for
   compiled objects before assuming a rebuild is needed.

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

## Path C — Bigtop publishes no aarch64 RPMs either · **contingent on SPIKE-A04**

The expensive case, and **no longer known to apply** — that depended on the withdrawn reading
of the Ambari site's x86_64 notice. Whether this path is needed at all is SPIKE-A04's answer.

It is also **materially cheaper than first estimated**, because the two hardest pieces are
supplied upstream: the ARM host image (`bigtop/puppet:3.3.0-rockylinux-8-aarch64`) and the ARM
build environment (`bigtop/slaves:3.3.0-rockylinux-8-aarch64`) both already exist for this
exact OS and Bigtop version. No toolchain assembly, no cross-compilation strategy.

Documented here so its cost is visible before it is chosen — and it must be *chosen*,
explicitly, by the project owner (`spec.md` § 8), against a measured estimate.

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

### SPIKE-A02 — Bigtop build toolchain on ARM64 · **MOSTLY RESOLVED 2026-08-27**

~~**Unknown.** Whether Bigtop's build container images are published for aarch64.~~

**Resolved: they are.** `bigtop/slaves:3.3.0-rockylinux-8-aarch64` exists — the aarch64 build
slave for exactly the OS and Bigtop version this project targets. Bigtop maintains ARM build
environments as part of its normal CI, so building on ARM is an exercised path rather than an
experiment. That removes the largest single risk from the build option: no cross-compilation
strategy is needed, and no bespoke toolchain has to be assembled.

**Still to confirm at T-A05** (execution details, not feasibility):

- The real Gradle task names and image tags for 3.3.0 — read them from that release's own
  `build.gradle` and documentation. **Do not guess them.**
- Whether the build runs acceptably on an Apple Silicon Docker Desktop VM, or wants a real
  ARM64 Linux host.
- Wall-clock and disk for a full stack build on ARM.

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
| 2026-08-27 | **SPIKE-A01** | **RESOLVED.** The official Ambari download page states "All packages are built for x86_64 architecture." No aarch64 packages at `apache-ambari.com`. |
| 2026-08-27 | ~~Path C at 3–6 weeks~~ | **SUPERSEDED, same day.** The initial reading — "Bigtop is x86_64 only" — was wrong. Bigtop supports AArch64; the limitation is the Ambari distribution site's build capacity. Estimate withdrawn pending SPIKE-A04. |
| 2026-08-27 | **SPIKE-A02** | **Mostly resolved.** `bigtop/slaves:3.3.0-rockylinux-8-aarch64` exists — Bigtop's ARM build environment for this exact OS and version. Building on ARM is CI-exercised, not experimental. |
| 2026-08-27 | Base image question | **Answered: yes.** `bigtop/puppet:3.3.0-rockylinux-8-aarch64` and `trunk-rockylinux-8-aarch64` exist. The host image does not need building. |
| 2026-08-27 | **SPIKE-A04** | **Opened.** Does Bigtop publish aarch64 RPMs at `repos.bigtop.apache.org`? Not verifiable from the drafting environment (proxy-blocked; a uniform 403 across all architectures proves nothing). Swings the estimate between ~1 week and ~1 month. **Check this first.** |
| 2026-08-27 | SPIKE-A03 | Still open. Native library completeness remains the real risk on any built-from-source path. |
