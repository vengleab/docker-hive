# Contract — CLI surface

The Makefile is the user interface (FR-020). Everything a user does routinely is one target.

Deliberately mirrors `docker-hive`'s `make start` / `make stop` / `make cleanup` vocabulary
where it can, so the muscle memory transfers.

---

## Primary targets

| Target | Does | Requirements |
|---|---|---|
| `make up` | Full provision: preflight → secrets → generate → mirror → build → compose up → install → report | FR-013, FR-021 |
| `make down` | Stop all containers. **Data preserved.** | FR-022 |
| `make destroy` | Stop and remove everything including volumes and networks | FR-022 |
| `make status` | Cluster state, host health, service states, in human terms | FR-016 |
| `make test` | The five smoke checks | FR-024 |
| `make logs` | Tail logs; `SERVICE=` scopes to one container | P6 |
| `make diagnose` | Full failure dump — see below | P6, FR-015 |
| `make shell` | Shell into a host; `HOST=master1` (default `ambari-server`) | — |

## Supporting targets

| Target | Does |
|---|---|
| `make preflight` | Check Docker, Compose, RAM, disk, port availability against the profile. Run automatically by `up`; exposed for standalone diagnosis. |
| `make generate` | Topology → compose + blueprint + template only. No containers touched. |
| `make validate` | Validation rules V1–V10 only. Fast; suitable for a pre-commit hook. |
| `make mirror` | Populate the local package mirror. Cached; safe to re-run. |
| `make build` | Build host images for the current platform. |
| `make build-multiarch` | `buildx` for `linux/amd64,linux/arm64` (feature 002). |
| `make migrate-config FILE=…` | Run `env2blueprint` on a legacy `hadoop-hive.env`; print blueprint `configurations[]`. (FR-017) |
| `make open` | Open Ambari Web in a browser. |

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `TOPOLOGY` | `cluster-topology.yaml` | Alternate topology file |
| `PROFILE` | *(from topology)* | Override the profile for one invocation |
| `PLATFORM` | *(host arch)* | `linux/amd64` or `linux/arm64` |
| `HOST` | `ambari-server` | Target for `shell` / `logs` |
| `TIMEOUT` | `3600` | Provision timeout, seconds |
| `VERBOSE` | `0` | `1` echoes every REST call |

---

## Output requirements

Binding on every target (constitution P6).

### Progress

Long operations print elapsed time, phase, and what is being waited on. Silence is a defect:

```
[00:00:04] preflight    ✔ docker 27.3.1, compose v2.29.7
[00:00:05] preflight    ✔ 32 GB RAM available (profile 'standard' needs 20 GB)
[00:00:06] preflight    ✔ ports 8080,19870,18088,19888,20000 free
[00:00:12] secrets      ✔ generated 4 secrets → secrets/
[00:00:14] generate     ✔ 3 host groups → 3 hosts; blueprint 'bigtop-dev-blueprint'
[00:02:31] mirror       ✔ 1,247 packages (cached, 0 downloaded)
[00:06:48] build        ✔ 4 images (linux/arm64)
[00:07:02] compose      ✔ 6 containers started
[00:08:30] gate:server  ⏳ waiting for Ambari server … 88s
[00:08:44] gate:server  ✔ Ambari server ready
[00:09:51] gate:hosts   ✔ 3/3 hosts registered and HEALTHY
[00:09:55] install      ⏳ INSTALLING  14%  (8/60)  DATANODE on worker1.ambari.local
...
[00:31:22] install      ✔ COMPLETED (60/60 tasks)
```

### Success

```
Cluster 'bigtop-dev' is INSTALLED and STARTED
  Hosts     3 (master1, worker1, worker2)  ·  Services  6  ·  Elapsed  00:31:22

  Ambari Web        http://localhost:8080     admin / see secrets/ambari-admin-password
  NameNode          http://localhost:19870
  ResourceManager   http://localhost:18088
  JobHistory        http://localhost:19888
  HiveServer2       jdbc:hive2://localhost:20000/default

  Next: make test
```

Note that "STARTED" is reported, not Ambari's raw `INSTALLED` — see `ambari-rest.md` step 7.

### Failure (FR-015)

Never a bare stack trace. Always: what failed, where, why, and what to do.

```
✘ Install FAILED at 62% (37/60 tasks)

  Failed tasks:
    ✘ DATANODE / INSTALL on worker2.ambari.local
      Error: Failed to download package hadoop-hdfs-datanode
      stderr (last 12 lines):
        Cannot download ... [Errno 14] curl#7 - "Failed to connect to repo.ambari.local:80"
        ...

  Likely cause: the package mirror is unreachable from worker2.
  Check: make logs SERVICE=repo
         make shell HOST=worker2  then  curl -I http://repo.ambari.local/

  Full transcript: logs/provision-20260827-141233.jsonl
  Full dump:       make diagnose
```

### `make diagnose`

Collects, into `diagnostics-<timestamp>.tar.gz`:

- `docker compose ps` and `docker stats --no-stream`
- last 500 lines from every container
- `/var/log/ambari-server/ambari-server.log`
- `/var/log/ambari-agent/ambari-agent.log` from every host
- the failed-task dump from the Ambari REST API
- `hostname -f`, `systemctl is-system-running`, and clock skew from every host
  *(failure modes F1, F4, F5)*
- the resolved topology, blueprint, and creation template, **secrets redacted**

---

## Behavioural requirements

1. **Idempotent** (P4, FR-021): `make up` twice converges. `make down` twice is not an error.
   `make destroy` on nothing is not an error.
2. **Resumable**: `make up` after an interrupted run resumes where Ambari permits, and says
   which phase it is resuming from.
3. **No interactive prompts** (P2) on any path. Destructive targets take `FORCE=1` rather than
   asking; `make destroy` without it prints what it would remove and requires the flag.
4. **Exit codes**: `0` success; `1` operation failed; `2` preflight/validation failed
   (nothing was changed); `3` timeout.
5. **Secrets never printed in full** (P7). Print the path, not the value.
6. **`make validate` and `make generate` touch no containers** and are safe in CI and in a
   pre-commit hook.
