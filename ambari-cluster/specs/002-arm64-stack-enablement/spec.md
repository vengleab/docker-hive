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

## 2. The central question — partly answered, and the first answer was misread

> **Does the ARM64 support this project needs actually exist upstream?**

**The Ambari distribution site: no.** Its download page states *"All packages are built for
x86_64 architecture."* (`../001-ambari-cluster-bootstrap/upstream-reference.md` § 5.)

**Apache Bigtop: yes.** This distinction was initially missed, and the feature was briefly
scoped as a 3–6 week from-scratch source build on that basis. **That estimate is withdrawn.**
Bigtop supports AArch64 and maintains ARM build infrastructure; the x86_64-only limitation
belongs to the Ambari distribution site's build capacity, not to the software.

Verified against Docker Hub, 2026-08-27:

```
bigtop/puppet:3.3.0-rockylinux-8-aarch64   ✔   the ARM host image — already exists
bigtop/slaves:3.3.0-rockylinux-8-aarch64   ✔   the ARM build environment — already exists
```

Those two are exactly the pieces that would have made a source build expensive, and both are
supplied upstream for the precise OS and Bigtop version this project targets.

**What is still unknown is narrow:** whether Bigtop *publishes* aarch64 RPMs at its own
repository (`repos.bigtop.apache.org`, whose repo definitions are `$basearch`-parameterised).
That is **SPIKE-A04**, and it swings the cost between roughly a week and roughly a month. It
could not be checked from the drafting environment — the host is proxy-blocked, and the
uniform 403 across every architecture is the proxy talking, not the server.

**Run SPIKE-A04 before committing to anything.** The scope decision (§ 8, T-A00) is still the
project owner's, but it should be taken against a measured answer rather than a withdrawn
estimate.

## 3. Decision tree

*(Retained as the record. Path selection now hinges on SPIKE-A04, not on the Ambari site.)*

```
                    T003: enumerate Bigtop 3.3.0 repos for aarch64
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
   PATH A: complete            PATH B: partial              PATH C: none
   Bigtop publishes all        Bigtop publishes some        Bigtop publishes none
   needed aarch64 RPMs         aarch64 RPMs                 at its own repo
        │                             │                             │
        ▼                             ▼                             ▼
   Point the mirror at         Mirror what exists,          Build the stack using
   Bigtop for the stack.       build the gap with           bigtop/slaves:3.3.0-
   Multi-arch images.          Bigtop's ARM slave.          rockylinux-8-aarch64.
   ~1 week.                    ~1-3 weeks.                  ~3-6 weeks.
```

**The host base image is no longer in scope on any path** —
`bigtop/puppet:3.3.0-rockylinux-8-aarch64` already exists.

**And on every path, `ambari-server` / `ambari-agent` still need handling**, since those come
from the Ambari site rather than Bigtop. They are largely Java and Python, so check whether
their `x86_64` tag reflects real native content before assuming a rebuild is needed.

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
| Bigtop publishes no aarch64 RPMs → source build needed | 3–6 weeks; feature 001's P5 release gate blocked until it lands | **SPIKE-A04 first.** Scope confirmed with the project owner before starting (§ 8). Use P5's time-boxed exception to ship amd64 meanwhile rather than holding the whole project. |
| ~~Upstream base image has no aarch64 variant~~ | — | **Retired** — `bigtop/puppet:3.3.0-rockylinux-8-aarch64` exists |
| ~~Bigtop's build toolchain is amd64-only~~ | — | **Retired** — `bigtop/slaves:3.3.0-rockylinux-8-aarch64` exists |
| `ambari-server` / `ambari-agent` are genuinely x86_64 | The management layer needs rebuilding even on Path A | Inspect the RPMs for real native content before assuming; they are largely Java and Python |
| A component cannot be built for aarch64 at all | That service is amd64-only | FR-A13: document it; consider dropping it from the default topology on ARM |
| Build produces subtly broken packages | Failures far from the cause | The smoke and parity suites are the gate — FR-A05, FR-A06 |
| Bigtop's build toolchain itself does not run on ARM | Cross-compilation or an amd64 build host needed | Investigate early; an amd64 build host producing aarch64 packages is an acceptable answer |
| JNI-heavy native libraries (Snappy, Hadoop native, LZO) missing on ARM | Degraded performance or runtime failures | Test explicitly — `docker-hive` uses Snappy compression, so this is a real path |
