# Data Model — Feature 001

The entities the system reasons about, their fields, their rules, and how they map onto
Ambari's own API resources.

```
VersionManifest ──pins──► StackVersion ──defines──► Service ──has──► Component
                                                                        │
ClusterTopology                                                     placed on
   │                                                                    │
   ├── Profile                                                          ▼
   ├── HostGroup ──contains──► Host ──runs──► ComponentInstance ◄───────┘
   └── ConfigOverride

ClusterTopology ──generates──► Blueprint + ClusterCreationTemplate + ComposeFile
                                     │
                                     └──submitted to──► Ambari ──creates──► Cluster
                                                                                │
                                                                          ProvisionRequest
                                                                                │
                                                                             Task[]
```

---

## Authored entities

These are written by a human. Everything else is derived.

### `VersionManifest` → `versions.yaml`

The single pinned source for every version in the project (constitution P3).

| Field | Type | Notes |
|---|---|---|
| `ambari.version` | string | `3.0.0` |
| `ambari.repo_url` | URL | `https://apache-ambari.com/dist/ambari/3.0.0/rocky8/` — confirmed |
| `stack.name` | string | `BIGTOP` — **exact value still unconfirmed**, see SPIKE-004 |
| `stack.version` | string | `3.3.0` |
| `stack.repo_url` | URL | `https://apache-ambari.com/dist/bigtop/3.3.0/rocky8/` — confirmed |
| `base_image` | string | **`bigtop/puppet:trunk-rockylinux-8`**, digest-pinned |
| `jdk.stack` | string | **Java 8** — runs the managed stack, passed as `-j` |
| `jdk.ambari` | string | **Java 17** — runs the Ambari server, passed as `--ambari-java-home` (D-010) |
| `postgres.version` | string | Digest-pinned |
| `components{}` | map | Informational: Hadoop 3.3.6, Hive 3.1.3, Spark 3.3.4, … |

**Rules.** No value may be `latest` or an unpinned tag. Every image reference carries a
digest. Changing this file is a deliberate, reviewed act.

### `ClusterTopology` → `cluster-topology.yaml`

The single source of truth for cluster shape (constitution P2). Full annotated contract:
`contracts/cluster-topology.yaml`.

| Field | Type | Notes |
|---|---|---|
| `cluster_name` | string | `[a-z][a-z0-9_-]{2,31}`; becomes the Ambari cluster name |
| `domain` | string | DNS suffix, e.g. `ambari.local`; every host FQDN is `<name>.<domain>` |
| `profile` | enum | `mini` \| `standard` \| `full` |
| `services[]` | list | Service names to install; must exist in the stack |
| `host_groups[]` | list of `HostGroup` | |
| `config_overrides[]` | list of `ConfigOverride` | Escape hatch for one-off tuning |

### `HostGroup`

An Ambari blueprint host group: a role played by one or more identical hosts.

| Field | Type | Notes |
|---|---|---|
| `name` | string | `master`, `worker`, `edge` |
| `cardinality` | int or `1+` | How many hosts; expands to `<name>1..N` |
| `components[]` | list | Component names placed on every host in the group |
| `resources.memory` | string | Compose `mem_limit`, e.g. `4g` |
| `resources.cpus` | number | Compose `cpus` |
| `volumes[]` | list | Named volumes, e.g. `/hadoop/hdfs/data` |

**Rules.**
- Names are unique within a topology.
- `cardinality` ≥ 1.
- A group with no components is invalid.
- Every referenced component must belong to an enabled service (FR-004).

### `ConfigOverride`

| Field | Type | Notes |
|---|---|---|
| `config_type` | string | `core-site`, `hdfs-site`, `yarn-site`, `hive-site`, … |
| `properties{}` | map | Property name → value, **in real dotted form** |

**Rule.** Property names are written plainly — `yarn.log-aggregation-enable`, not
`yarn_log___aggregation___enable`. The predecessor's underscore encoding exists only as
*input* to the migration tool (FR-017) and never appears in this project's own files.

---

## Derived entities

Generated, gitignored, never hand-edited (D-009).

### `Host`

Expanded from a `HostGroup` by cardinality.

| Field | Derivation |
|---|---|
| `name` | `<group>` + ordinal, e.g. `worker2` |
| `fqdn` | `<name>.<domain>`, e.g. `worker2.ambari.local` |
| `group` | Owning host group |
| `components[]` | Copied from the group |

**Invariants** — these are the FR-007 requirements restated as checkable facts:
- `hostname -f` inside the container returns exactly `fqdn`.
- `fqdn` resolves from every other host and from `ambari-server`.
- `fqdn` is what the agent reports at registration and therefore what appears in
  `GET /api/v1/hosts`. A mismatch here is failure mode **F1**.

### `Blueprint`

The Ambari blueprint. Shape contract: `contracts/blueprint.md`.

| Field | Derivation |
|---|---|
| `Blueprints.stack_name` / `stack_version` | `VersionManifest.stack` |
| `host_groups[].name` / `cardinality` | `ClusterTopology.host_groups[]` |
| `host_groups[].components[]` | Same |
| `configurations[]` | Service defaults + migrated legacy tuning + `config_overrides[]`, in that precedence order (last wins) |

### `ClusterCreationTemplate`

Binds blueprint host groups to concrete FQDNs.

| Field | Derivation |
|---|---|
| `blueprint` | Blueprint name |
| `host_groups[].name` | Group name |
| `host_groups[].hosts[].fqdn` | Expanded `Host.fqdn` values |

### `ComposeFile`

One service per `Host`, plus the three infrastructure containers. Carries the FQDN as
`hostname`, the matching network alias, the resource limits, the volumes, and the
systemd-in-Docker keys resolved by SPIKE-003.

---

## Ambari-side entities

Owned by Ambari; this project observes them. Field names follow Ambari's API.

### `Cluster`
`cluster_name`, `version` (`<stack>-<version>`), `provisioning_state`
(`INIT` → `INSTALLING` → `INSTALLED`). Endpoint: `/api/v1/clusters/{name}`.

### `RegisteredHost`
`host_name` (the FQDN), `host_status` (`HEALTHY`/`UNHEALTHY`/`HEARTBEAT_LOST`),
`last_heartbeat_time`, `total_mem`, `cpu_count`, `os_type`, `os_arch`.
Endpoint: `/api/v1/hosts`.

`os_arch` is the field feature 002 keys on to confirm a native aarch64 host.

### `ServiceInstance`
`service_name`, `state` (`INSTALLED` = stopped, `STARTED` = running), `maintenance_state`.
Endpoint: `/api/v1/clusters/{c}/services/{s}`.

The `INSTALLED` ≠ running distinction is the single most common source of confusion when
reading Ambari's API. Wrappers must translate it in user-facing output (FR-016).

### `ProvisionRequest` and `Task`

`ProvisionRequest`: `id`, `request_status` (`PENDING`/`IN_PROGRESS`/`COMPLETED`/`FAILED`/
`ABORTED`), `progress_percent`, `task_count`, `completed_task_count`.
Endpoint: `/api/v1/clusters/{c}/requests/{id}`.

`Task`: `id`, `host_name`, `role`, `command`, `status`, `stderr`, `stdout`, `error_log`.
Endpoint: `…/requests/{id}/tasks`.

**This is the FR-015 payload.** On `FAILED`, the diagnostic dump enumerates tasks with
`status == FAILED` and prints `host_name`, `role`, `command`, and the tail of `stderr`. A bare
"request failed" is a constitution P6 violation.

---

## Validation rules (FR-004)

Enforced by `tools/validate.py` before anything is generated. Each must produce a specific,
actionable message naming the offending field.

| # | Rule |
|---|---|
| V1 | Every `services[]` entry exists in the stack |
| V2 | Every component belongs to an enabled service |
| V3 | Single-instance components (NAMENODE, RESOURCEMANAGER, HIVE_METASTORE) appear in exactly one host group with cardinality 1 |
| V4 | Service dependencies are satisfied — HBASE ⇒ ZOOKEEPER, HIVE ⇒ HDFS + YARN + a metastore DB, YARN ⇒ HDFS |
| V5 | At least one DATANODE and one NODEMANAGER exist when HDFS/YARN are enabled |
| V6 | `dfs.replication` ≤ DataNode count |
| V7 | Host group names are unique; expanded FQDNs are unique; **and every hostname, FQDN label, network name, and the Compose project name matches `[a-z0-9]([a-z0-9-]*[a-z0-9])?` — no underscores** (D-011, F11). Compose derives network names from the project name, which is how the predecessor got its `java.net.URISyntaxException` |
| V8 | Requested memory across all hosts does not exceed the profile's declared budget |
| V9 | No `config_overrides[]` property name contains `___` or `__` — that is predecessor encoding leaking in |
| V10 | Host-port assignments do not collide with each other or with `docker-hive`'s documented map (F8) |
