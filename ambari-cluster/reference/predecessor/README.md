# Predecessor reference material

**Everything the specs need from the predecessor project, embedded here verbatim.**

## Why this directory exists

These specifications describe replacing a hand-rolled Docker Hadoop cluster (`docker-hive`)
with an Ambari-managed one. Several tasks need material *from* that project: its configuration
values to migrate, its test fixtures to port, its port map to avoid colliding with.

If those tasks said "copy this file from `docker-hive`", the spec package would only work for
someone who also has that repository. **It doesn't.** This package is designed to be lifted
into a new, empty project and remain fully executable, so every input it needs is copied in
here instead.

Constitution **P9** states the rule: the predecessor is prior art, never a dependency. This
directory is how that rule is kept.

## What is here

| File | Used by | Purpose |
|---|---|---|
| `hadoop-hive.env` | 001 · T014 (FR-017/018/019) | The legacy configuration to migrate. Input to `env2blueprint`. |
| `entrypoint-configure.sh` | 001 · T014 | The `sed`-into-XML mechanism being replaced. Defines the encoding the migration tool must decode. |
| `spark_yarn_pi.py` | 003 · T-P07 | Spark-on-YARN parity fixture. |
| `submit_yarn.sh` | 003 · T-P07 | Its submit wrapper. |
| `notebook-workload.md` | 003 · T-P02, T-P04 | The teaching notebook's operations, described precisely enough to rebuild as a headless fixture. |
| `topology-and-ports.md` | 001 · FR-023, T024 | The predecessor's services and host ports, so the new port map avoids collisions (failure mode F8). |

## Provenance

Taken from `github.com/vengleab/docker-hive` @ `b2da7c2`, 2026-08-27. Files marked *verbatim*
are unmodified. Nothing here is executed by this project; it is input data and reference.

## Rules

- **Read-only.** Do not "fix" these files. Their value is that they record what the predecessor
  actually does, including its bugs — several of which the specs deliberately correct.
- **Do not add a path back to `docker-hive`.** If a task needs something not here, copy it in
  and update this index.
- Prose elsewhere in the specs may *refer* to `docker-hive` as prior art. That is fine. What is
  forbidden is a task that cannot run without it.
