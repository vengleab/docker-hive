# Contract — Ambari REST provisioning sequence

The headless install (FR-013). Implemented by `tools/provision.py`.

> ⚠ **SPIKE-004 is open.** The blueprint and cluster-creation-template shapes below have been
> stable across Ambari's history and are low risk. The **repository-version registration**
> (step 3) and the **stack identifier strings** are *not* confirmed for Ambari 3.0.0 +
> BIGTOP 3.3.0. This document could not be validated against a live server or upstream
> documentation during drafting (network egress was restricted).
>
> **The running Ambari server is the authoritative source, not this document.** Task T004
> introspects it and amends this contract before any dependent code is written. Do not treat
> the payloads below as verified fact (constitution P10).

---

## Conventions

- Base URL: `http://ambari-server.ambari.local:8080/api/v1`
- Auth: HTTP Basic, `admin` + the password in `secrets/ambari-admin-password`
- **Every mutating request** requires the header `X-Requested-By: ambari` — Ambari's CSRF
  guard rejects requests without it with a `403` and an unhelpful message. This is the single
  most common first-time integration failure.
- `Content-Type: application/json`

---

## Step 0 — Discover the truth (T004, resolves SPIKE-004)

Run these first and record the responses in `research.md`. **The results override this
document.**

```http
GET /api/v1/stacks
GET /api/v1/stacks/{stack_name}/versions
GET /api/v1/stacks/{stack_name}/versions/{stack_version}?fields=*
GET /api/v1/stacks/{stack_name}/versions/{stack_version}/services?fields=*
GET /api/v1/version_definitions?fields=*
```

Specifically confirm: the exact `stack_name` (`BIGTOP` vs `BGTP` vs something else), the exact
`stack_version`, the `operating_systems` identifier for Rocky 8 (`redhat8`, `rocky8`, or
other), and which repository-registration flow the server accepts.

---

## Step 1 — Server readiness gate (FR-014)

```http
GET /api/v1/clusters
```

Poll until `200`. Anything else — connection refused, `503`, an HTML error page — means the
server is still starting. Bounded timeout; on expiry dump `ambari-server` container logs
(constitution P6).

## Step 2 — Host registration gate (FR-014)

```http
GET /api/v1/hosts
```

Poll until the response contains every expected FQDN from the generated topology, and each
host's `host_status` is `HEALTHY`:

```http
GET /api/v1/hosts?fields=Hosts/host_name,Hosts/host_status,Hosts/os_arch,Hosts/total_mem
```

**Assertions.** Host names must match the generated FQDNs *exactly*. A short hostname or a
container ID here is failure mode **F1** — fail fast with a message naming both the expected
and the reported name rather than proceeding to a blueprint that cannot map.

`Hosts/os_arch` is recorded here; feature 002 asserts it is `aarch64` on ARM builds.

On timeout, dump each missing host's `/var/log/ambari-agent/ambari-agent.log`.

## Step 3 — Register the repository version ⚠ *(SPIKE-004)*

Point the stack at the local mirror (D-005) so hosts install from `repo.ambari.local` rather
than upstream.

Two flows are believed to exist; **T004 determines which applies.**

**Flow A — version definition file (VDF):**
```http
POST /api/v1/version_definitions
{
  "VersionDefinition": {
    "version_url": "http://repo.ambari.local/vdf/BIGTOP-3.3.0.xml"
  }
}
```

**Flow B — direct repository update:**
```http
PUT /api/v1/stacks/{stack}/versions/{version}/operating_systems/{os}/repositories/{repo_id}
{
  "Repositories": {
    "base_url": "http://repo.ambari.local/bigtop/3.3.0/rocky8",
    "verify_base_url": true
  }
}
```

Verify afterwards that the registered `base_url` is the mirror, not an upstream URL. Installing
from upstream by accident violates FR-012 and will not be noticed until the offline test fails.

## Step 4 — Submit the blueprint

```http
POST /api/v1/blueprints/{blueprint_name}
```

Body: the generated blueprint (shape in `blueprint.md`). Expect `201`.

**Idempotency (P4):** a blueprint of this name may already exist from a previous run. Either
`DELETE` it first or treat `409 Conflict` as success when the stored blueprint is identical.
Do not silently proceed against a *different* stored blueprint — that produces a cluster which
does not match the topology file, and the mismatch is very hard to diagnose later.

## Step 5 — Create the cluster

```http
POST /api/v1/clusters/{cluster_name}
```

Body: the generated cluster creation template (shape in `blueprint.md`).

Returns `202` with a request href:
```json
{ "Requests": { "id": 1, "status": "InProgress",
                "href": ".../clusters/bigtop-dev/requests/1" } }
```

Capture `Requests.id`. Everything after this is polling.

## Step 6 — Poll to completion (FR-015)

```http
GET /api/v1/clusters/{cluster}/requests/{id}?fields=Requests/request_status,Requests/progress_percent,Requests/task_count,Requests/completed_task_count
```

Poll on a fixed interval. Print progress (P6):
```
[00:12:31] INSTALLING  62%  (37/60 tasks)  current: DATANODE on worker2.ambari.local
```

Terminal states: `COMPLETED` (success), `FAILED`, `ABORTED`, `TIMEDOUT`.

**On any non-`COMPLETED` terminal state, this is mandatory, not optional:**

```http
GET /api/v1/clusters/{cluster}/requests/{id}/tasks?fields=Tasks/host_name,Tasks/role,Tasks/command,Tasks/status,Tasks/stderr,Tasks/error_log
```

Filter to `Tasks/status == FAILED` and print, per task: host, role, command, and the last ~40
lines of `stderr`. A bare non-zero exit is a **constitution P6 violation** — the whole point is
that a failure at task 40 of 60 tells you *which* task and *why* without reading five
containers' logs by hand.

## Step 7 — Verify the terminal state (FR-016)

```http
GET /api/v1/clusters/{cluster}?fields=Clusters/provisioning_state
GET /api/v1/clusters/{cluster}/services?fields=ServiceInfo/service_name,ServiceInfo/state
```

Every service should report `state: STARTED`.

> **`INSTALLED` means stopped, not running.** This trips up everyone reading Ambari's API for
> the first time. User-facing output must translate it (FR-016) rather than echoing it.

---

## Post-install operations

### Service checks (FR-024, P8)

```http
POST /api/v1/clusters/{cluster}/requests
{
  "RequestInfo": {
    "context": "HDFS Service Check",
    "command": "HDFS_SERVICE_CHECK"
  },
  "Requests/resource_filters": [ { "service_name": "HDFS" } ]
}
```

Returns a request id; poll it exactly as in step 6. Repeat per service.

### Stop / start a service (scenario S3)

```http
PUT /api/v1/clusters/{cluster}/services/{service}
{
  "RequestInfo": { "context": "Stop HDFS" },
  "ServiceInfo":  { "state": "INSTALLED" }
}
```
`INSTALLED` stops, `STARTED` starts. Asynchronous — returns a request id to poll.

### Component state on one host

```http
GET /api/v1/clusters/{cluster}/hosts/{fqdn}/host_components/{component}?fields=HostRoles/state
```

---

## Implementation requirements

Binding on `tools/provision.py`:

1. **Every** poll has a bounded timeout and a diagnostic dump on expiry (P6).
2. **Every** mutating call carries `X-Requested-By`.
3. Non-2xx responses print the **response body**, not just the status code — Ambari's errors
   are usually informative and usually discarded by naive clients.
4. The whole sequence is re-runnable (P4): detect an existing cluster and resume or report
   clearly, never crash on "already exists".
5. Credentials are read from `secrets/` and never logged (P7).
6. The exact request/response of every call is written to `logs/provision-<timestamp>.jsonl`
   with secrets redacted — this is the artifact that makes a failed install debuggable after
   the fact.
