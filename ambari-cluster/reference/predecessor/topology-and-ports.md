# Predecessor topology and port map

Reference data for feature 001 (FR-023, T024). Recorded from `docker-hive` @ `b2da7c2` so the
new project's port map can avoid collisions without needing that repository present.

## Why this matters

A learner may well run both clusters on the same machine — the old one to compare against, the
new one to learn on. If host ports collide, the second `docker compose up` fails with a
confusing bind error. This is **failure mode F8**.

## Predecessor host ports

| Service | Host port | Container port | Notes |
|---|---|---|---|
| Hue | 8889 | 8888 | Dropped in the new project (D-008) |
| Spark Notebook (Jupyter) | 8888 | 8888 | Optional `edge` host in the new project |
| Spark application UI | 4040 | 4040 | |
| NameNode UI | 9870 | 9870 | |
| NameNode RPC | 9000 | 9000 | Note: the new project uses Ambari's default **8020** |
| DataNode UI | 9864 | 9864 | |
| YARN ResourceManager UI | 8088 | 8088 | |
| NodeManager UI | 8042 | 8042 | |
| MapReduce History / Timeline | 8188 | 8188 | |
| HiveServer2 (Thrift) | 10000 | 10000 | |
| Hive Metastore (Thrift) | 9083 | 9083 | |
| PostgreSQL (Hive metastore) | 5432 | 5432 | |
| Portainer | 3000 | 9000 | Not carried over |

## The new project's map

Chosen to avoid every port above. Defined in
`../../specs/001-ambari-cluster-bootstrap/contracts/cluster-topology.yaml` § expose:

| Service | New host port | Predecessor used |
|---|---|---|
| Ambari Web | 8080 | *(none — no collision)* |
| NameNode UI | 19870 | 9870 |
| ResourceManager UI | 18088 | 8088 |
| JobHistory UI | 19888 | 8188 |
| HiveServer2 | 20000 | 10000 |
| Jupyter (edge host) | 18888 | 8888 |

Validation rule **V10** enforces this: generated host-port assignments must not collide with
each other or with the table above.

## Predecessor service topology

Twelve Compose services, one daemon per container, no host abstraction:

```
namenode · datanode · resourcemanager · nodemanager · historyserver
hive-server · hive-metastore · hive-metastore-postgresql
spark-notebook · hue · portainer          (minio present but commented out)
```

Notable absences that shaped this project's design: **no ZooKeeper**, no SSH, no HA, no
secondary NameNode, no journal nodes, and no concept of a host that could run more than one
component.

## The network-name workaround

The predecessor's Compose file carries this comment:

```yaml
# solve java.net.URISyntaxException Illegal character in hostname at index 49:
#   thrift://docker-hive-hive-metastore-1.docker-hive_default:9083
networks:
  default:
    name: docker-hive-default
```

The illegal character is the **underscore** in the Compose-generated network name
`docker-hive_default`. Compose derives network names from the project name; the fix was to
name the network explicitly with hyphens.

This is the direct evidence behind decision **D-011** and failure mode **F11**, and the reason
this project forbids underscores in hostnames, network names, and the Compose project name —
including in Ambari's own documented naming (`bigtop_hostname0`), which would hit the same
exception in the same component.

## Component versions

For the parity claim in feature 003. Bigtop 3.3.0 matches the first two exactly.

| Component | Predecessor | Bigtop 3.3.0 | |
|---|---|---|---|
| Hadoop | 3.3.6 | 3.3.6 | identical |
| Hive | 3.1.3 | 3.1.3 | identical |
| Spark | 3.5.5 | 3.3.4 | **regression** — D-002 |
| Java | OpenJDK 8 **JRE** | JDK 8 (stack) + JDK 17 (Ambari) | D-010 |
| PostgreSQL | unpinned `latest` | pinned | P3 |
| Delta Lake | 2.4.0 | *(not in stack)* | pairs with Spark 3.3.x anyway |
