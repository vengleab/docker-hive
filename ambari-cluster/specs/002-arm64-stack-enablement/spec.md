# Feature 002 — ARM64 stack enablement

**Status:** Draft · **Depends on:** 001 (T003 in particular) · **Blocks:** the P5 release gate

---

## 1. Why

`docker-hive` runs natively on Apple Silicon. Every one of its `buildx` targets is
`--platform linux/amd64,linux/arm64`, and its Hadoop base image explicitly selects
`hadoop-3.3.6-aarch64.tar.gz` when `TARGETARCH=arm64`. That was deliberate work, and a large
share of the project's audience — students on M-series MacBooks — depends on it.

The successor cannot regress it. Constitution **P5** makes multi-arch parity a release gate,
not a nice-to-have.

But the mechanism changes completely. `docker-hive` gets ARM support for free because Apache
publishes an official aarch64 **tarball** of Hadoop. This project installs from **RPM
packages** built by Bigtop, and whether Bigtop 3.3.0 publishes aarch64 RPMs is **not
confirmed**. Apache Bigtop has had ARM64/AArch64 support work for several release cycles, but
per-release, per-component package availability is a different question from "the project
supports the architecture".

This feature exists because the answer might be "no", and if it is, the work required is
substantial enough to deserve its own spec rather than being buried as a task in feature 001.

## 2. The central question — **answered, 2026-08-27**

> **SPIKE-A01 — Does Bigtop 3.3.0 publish aarch64 RPMs for the components this project needs,
> for the base OS this project uses?**
>
> ## **No.**
>
> The official Apache Ambari download page states: *"All packages are built for x86_64
> architecture."* Only Rocky 8 and Rocky 9 x86_64 builds are published. Transcribed in
> `../001-ambari-cluster-bootstrap/upstream-reference.md` § 5.

**This puts the feature on Path C — build the Bigtop 3.3.0 stack from source. Estimated
3–6 weeks.**

That is a large enough commitment that it must be an explicit decision by the project owner,
not something absorbed into a sprint. See § 8. Constitution P5 makes ARM64 a release gate and
also provides the time-boxed exception if the owner judges the cost too high; either answer is
legitimate, but the question must be put.

**One thing could shrink this materially.** `ambari-server` and `ambari-agent` are largely Java
and Python. If their `x86_64` tag is packaging metadata rather than real native content, the
management layer may be cheaply rebuildable and only the *stack* needs a genuine build. T-A01
checks this first, because it is the difference between three weeks and six.

## 3. Decision tree

*(Retained as the record of how the path was chosen. **Path C is confirmed.**)*

```
                    T003: enumerate Bigtop 3.3.0 repos for aarch64
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
   PATH A: complete            PATH B: partial              PATH C: none  ◄── CONFIRMED
   All needed components       Some components have         No aarch64 RPMs
   have aarch64 RPMs           aarch64, others do not       published at all
        │                             │                             │
        ▼                             ▼                             ▼
   Mirror them.                Mirror what exists.           Build the whole
   Multi-arch images.          Build only the gap.           stack from source.
   ~2-3 days.                  ~1-2 weeks.                   ~3-6 weeks.
   RULED OUT                   RULED OUT (stack)             ◄── THIS ONE
```

Also newly in scope on Path C: the **host base image** itself. Upstream's
`bigtop/puppet:trunk-rockylinux-8` may have no aarch64 variant, in which case it must be built
before any package work can begin. T-A01 checks this first.

The estimates are order-of-magnitude, stated so the cost is visible **before** anyone commits.
Path C is a serious undertaking and its scope must be confirmed with the project owner rather
than absorbed silently.

## 4. Functional requirements

### Common to all paths

- **FR-A01** Every image the project builds MUST be produced for both `linux/amd64` and
  `linux/arm64`.
- **FR-A02** The package mirror MUST serve architecture-appropriate packages, and a host MUST
  install the correct architecture without per-architecture configuration in the topology file.
- **FR-A03** `make up` on an ARM64 machine MUST require **no** extra flags, no separate
  topology, and no emulation. Same command, same file.
- **FR-A04** `GET /api/v1/hosts` MUST report `Hosts/os_arch: aarch64` for every host on an
  ARM64 build. This is the machine-checkable proof that the cluster is native rather than
  emulated.
- **FR-A05** The full feature-001 smoke suite MUST pass on `linux/arm64`.
- **FR-A06** The feature-003 parity suite MUST pass on `linux/arm64`.
- **FR-A07** The architecture support matrix — which components are native, which are built
  locally, which are unavailable — MUST be documented.

### Path A / B only

- **FR-A08** Mirroring MUST fetch the correct architecture's packages based on the build
  platform, and MUST fail loudly rather than silently falling back to `x86_64` packages that
  would then fail to install on the host.

### Path B / C only — building from source

- **FR-A09** The project MUST provide a reproducible, documented build pipeline producing
  aarch64 RPMs for the missing components, using Apache Bigtop's own toolchain rather than a
  bespoke one.
- **FR-A10** Locally built packages MUST be publishable into the feature-001 mirror, with
  `createrepo` metadata regenerated automatically (failure mode F7).
- **FR-A11** Built packages MUST be cacheable and versioned so a rebuild is not required on
  every `make up`. Build time is measured in hours; paying it repeatedly is not acceptable.
- **FR-A12** The build pipeline MUST record, per component, the Bigtop version, the source
  commit, the build host architecture, and the build date.
- **FR-A13** Any component that cannot be built for aarch64 MUST be documented as unsupported
  on that architecture, with the reason, rather than failing obscurely at install time.

## 5. Non-functional requirements

- **NFR-A01** Native ARM64 performance MUST be materially better than amd64-under-emulation on
  the same machine. Measured, not assumed — emulated Hadoop on Docker Desktop is slow enough
  that the difference should be obvious.
- **NFR-A02** (Path B/C) A full package build completes in ≤ 12 hours on a developer machine
  and is resumable after interruption.
- **NFR-A03** (Path B/C) Built artefacts are cached so an incremental rebuild of one component
  does not rebuild the stack.

## 6. Acceptance criteria

1. `make up` on an ARM64 machine produces a working cluster with no extra flags. *(FR-A03)*
2. Every host reports `os_arch: aarch64`. *(FR-A04)*
3. `make test` passes 5/5 on ARM64. *(FR-A05)*
4. The feature-003 parity suite passes on ARM64. *(FR-A06)*
5. `docker buildx imagetools inspect` shows both platforms for every published image.
   *(FR-A01)*
6. The support matrix is published and accurate. *(FR-A07)*
7. **Path B/C only:** a from-scratch package build succeeds on a clean machine following the
   documentation alone. *(FR-A09)*
8. A native-vs-emulated benchmark is recorded in the docs. *(NFR-A01)*

## 7. Explicitly out of scope

- Architectures other than `x86_64` and `aarch64` (no ppc64le, no s390x, no riscv64).
- Upstreaming locally-built packages to Apache Bigtop. Worth doing, worth a conversation with
  that community, but not this feature.
- Optimising Hadoop for ARM beyond making it work correctly.
- Rebuilding components the project does not install.

## 8. Risk

| Risk | Impact | Mitigation |
|---|---|---|
| ~~Path C confirmed~~ — **this has happened** | 3–6 weeks of work; feature 001's P5 release gate blocked until it lands | Scope must be confirmed with the project owner before starting (§ 8). Use P5's time-boxed exception to ship amd64 while the build pipeline is developed, rather than holding the whole project. |
| Upstream base image has no aarch64 variant | The host image must be built too, before any package work | T-A01 checks this first |
| A component cannot be built for aarch64 at all | That service is amd64-only | FR-A13: document it; consider dropping it from the default topology on ARM |
| Build produces subtly broken packages | Failures far from the cause | The smoke and parity suites are the gate — FR-A05, FR-A06 |
| Bigtop's build toolchain itself does not run on ARM | Cross-compilation or an amd64 build host needed | Investigate early; an amd64 build host producing aarch64 packages is an acceptable answer |
| JNI-heavy native libraries (Snappy, Hadoop native, LZO) missing on ARM | Degraded performance or runtime failures | Test explicitly — `docker-hive` uses Snappy compression, so this is a real path |
