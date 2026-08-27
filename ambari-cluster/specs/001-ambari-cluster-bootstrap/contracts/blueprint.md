# Contract — Ambari blueprint and cluster creation template

The two generated JSON documents that define the cluster (FR-002). Produced by
`tools/generate.py` from `cluster-topology.yaml`; submitted per `ambari-rest.md` steps 4–5.

> Blueprint shape has been stable across Ambari releases and is **low risk**. The `stack_name`
> and `stack_version` values are **not confirmed** for Ambari 3.0.0 + Bigtop 3.3.0 — see
> SPIKE-004. T004 confirms them from the live server before generation is written.

---

## 1. Blueprint

Declares *what the cluster is*, independent of which machines run it. It names the stack, the
host groups, the components per group, and the configuration.

```json
{
  "Blueprints": {
    "blueprint_name": "bigtop-dev-blueprint",
    "stack_name": "BIGTOP",
    "stack_version": "3.3.0"
  },

  "configurations": [
    {
      "core-site": {
        "properties": {
          "fs.defaultFS": "hdfs://master1.ambari.local:8020"
        }
      }
    },
    {
      "hdfs-site": {
        "properties": {
          "dfs.replication": "2"
        }
      }
    },
    {
      "yarn-site": {
        "properties": {
          "yarn.log-aggregation-enable": "true",
          "yarn.nodemanager.resource.memory-mb": "16384",
          "yarn.nodemanager.resource.cpu-vcores": "8",
          "yarn.timeline-service.enabled": "true"
        }
      }
    },
    {
      "hive-site": {
        "properties": {
          "javax.jdo.option.ConnectionURL": "jdbc:postgresql://ambari-db.ambari.local:5432/hive",
          "javax.jdo.option.ConnectionDriverName": "org.postgresql.Driver",
          "javax.jdo.option.ConnectionUserName": "hive",
          "javax.jdo.option.ConnectionPassword": "${SECRET:hive_db_password}",
          "hive.support.concurrency": "true",
          "hive.txn.manager": "org.apache.hadoop.hive.ql.lockmgr.DbTxnManager"
        }
      }
    },
    {
      "hive-env": {
        "properties": {
          "hive_database": "Existing PostgreSQL Database",
          "hive_database_type": "postgres"
        }
      }
    }
  ],

  "host_groups": [
    {
      "name": "master",
      "cardinality": "1",
      "components": [
        { "name": "NAMENODE" },
        { "name": "SECONDARY_NAMENODE" },
        { "name": "RESOURCEMANAGER" },
        { "name": "HISTORYSERVER" },
        { "name": "APP_TIMELINE_SERVER" },
        { "name": "ZOOKEEPER_SERVER" },
        { "name": "HIVE_METASTORE" },
        { "name": "HIVE_SERVER" },
        { "name": "METRICS_COLLECTOR" },
        { "name": "METRICS_MONITOR" },
        { "name": "HDFS_CLIENT" },
        { "name": "YARN_CLIENT" },
        { "name": "MAPREDUCE2_CLIENT" },
        { "name": "HIVE_CLIENT" },
        { "name": "TEZ_CLIENT" },
        { "name": "ZOOKEEPER_CLIENT" }
      ]
    },
    {
      "name": "worker",
      "cardinality": "2",
      "components": [
        { "name": "DATANODE" },
        { "name": "NODEMANAGER" },
        { "name": "METRICS_MONITOR" },
        { "name": "HDFS_CLIENT" },
        { "name": "YARN_CLIENT" },
        { "name": "MAPREDUCE2_CLIENT" }
      ]
    }
  ]
}
```

### Rules

- **`configurations` is an array of single-key objects**, one per config type. It is not a
  map. Getting this wrong produces a `400` with a vague message.
- **All values are strings.** `"true"`, not `true`. `"2"`, not `2`. Numeric and boolean JSON
  literals are rejected.
- **Property names are real and dotted.** `yarn.log-aggregation-enable`. The predecessor's
  `yarn_log___aggregation___enable` encoding never appears here (rule V9).
- **`${SECRET:name}` placeholders** are substituted from `secrets/` immediately before
  submission, never written to disk in resolved form (constitution P7).
- **`cardinality` is a string**: `"1"`, `"2"`, or `"1+"`.
- **Explicit heap sizes.** Where memory matters, set it here rather than relying on the stack
  advisor's recommendations — inside containers it reads the *host's* memory and produces
  unusable values. This is failure mode **F6**.

### Config precedence

```
stack service defaults
  → migrated legacy tuning        (env2blueprint.py output, FR-017)
    → cluster-topology.yaml config_overrides[]
      → ${SECRET:...} substitution
```
Last wins. `generate.py` resolves this and emits the flattened result.

---

## 2. Cluster creation template

Binds abstract host groups to concrete hosts. This is the only place FQDNs appear.

```json
{
  "blueprint": "bigtop-dev-blueprint",
  "default_password": "${SECRET:default_service_password}",
  "host_groups": [
    {
      "name": "master",
      "hosts": [ { "fqdn": "master1.ambari.local" } ]
    },
    {
      "name": "worker",
      "hosts": [
        { "fqdn": "worker1.ambari.local" },
        { "fqdn": "worker2.ambari.local" }
      ]
    }
  ]
}
```

### Rules

- **Host count per group must match the blueprint's `cardinality` exactly.** A mismatch fails
  at `POST` time with a message that does not name the offending group; `validate.py` should
  catch it first (rule V7).
- **`fqdn` values must byte-match what `GET /api/v1/hosts` reports.** Not the short name, not
  the container ID, not a different case. This is failure mode **F1**, and it is the most
  common cause of a blueprint install refusing to start.
- `default_password` seeds service accounts that require one; it comes from `secrets/`.

---

## 3. Generation requirements

Binding on `tools/generate.py`:

1. **Deterministic** (FR-002): identical `cluster-topology.yaml` + `versions.yaml` produce
   byte-identical JSON. Sort keys; sort component lists; do not embed timestamps, hostnames,
   usernames, or random values.
2. **Validated before generation** (FR-004): `validate.py` rules V1–V10 run first and abort on
   any failure with a message naming the field.
3. **Secrets stay symbolic** on disk: generated files contain `${SECRET:...}`, resolved only
   in memory at submission time (P7).
4. **Traceable**: each generated file carries a header comment naming the source topology file
   and its content hash, so a dumped artifact can be traced back to its input.
5. **Never committed** (D-009): output goes to gitignored `generated/`.

## 4. Verification

- `generate.py` run twice produces identical output (`diff` is empty).
- Generated JSON validates against the Ambari blueprint schema exposed by the live server.
- A generated blueprint round-trips: `POST` it, then `GET /api/v1/blueprints/{name}` and
  confirm the stored form matches what was sent, modulo Ambari's own normalisation.
- No generated file contains a resolved secret: `grep -r "password.*:.*[^}]$" generated/`
  finds nothing outside `${SECRET:...}` placeholders.
