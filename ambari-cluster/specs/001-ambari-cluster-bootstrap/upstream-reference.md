# Upstream reference — the official Ambari Docker procedure

**Source:** the Apache Ambari website, `docs/quick-start/` — `docker-environment-setup.md`,
`installation-guide.md`, `download.md`, `quick-start-guide.md`. Retrieved **2026-08-27** from
the site's own source repository (`apache/ambari-website`, branch `main`), because
`ambari.apache.org` was unreachable from the drafting environment.

**Why this file exists.** It is the verified ground truth this specification is built on, and
it is recorded here so the project does not depend on that site being reachable later. The
official pages describe a **manual runbook**: `docker exec` into each container and type
commands. This project automates that runbook. Everything below is what upstream actually
says; the appraisal at the end is this project's own judgement.

---

## 1. The official Compose file

Four containers: one server (`bigtop_hostname0`, port 8080 published) and three agents.

```yaml
version: '3'

services:
  bigtop_hostname0:
    command: /sbin/init
    domainname: bigtop.apache.org
    image: bigtop/puppet:trunk-rockylinux-8
    mem_limit: 8g
    mem_swappiness: 0
    ports:
      - "8080:8080"
    privileged: true
    volumes:
      - ./ambari-repo:/var/repo/ambari
      - ./conf/hosts:/etc/hosts

  bigtop_hostname1:      # ... hostname2, hostname3 identical, no published ports
    command: /sbin/init
    domainname: bigtop.apache.org
    image: bigtop/puppet:trunk-rockylinux-8
    mem_limit: 8g
    mem_swappiness: 0
    privileged: true
    volumes:
      - ./ambari-repo:/var/repo/ambari
      - ./conf/hosts:/etc/hosts
```

**Stated prerequisites:** Docker Engine ≥ 20.10, Compose ≥ 2.0, **≥ 8 GB free RAM for a
4-node cluster**, ≥ 20 GB disk.

### What this settles

| Question | Upstream answer |
|---|---|
| Base image | **`bigtop/puppet:trunk-rockylinux-8`** — Rocky 8 with Java, Puppet, and Hadoop build/runtime dependencies preinstalled. Not a bare Rocky image. |
| systemd | `command: /sbin/init` |
| Privileges | **`privileged: true`** — no cgroup bind-mounts, no `tmpfs` on `/run`, no `stop_signal: SIGRTMIN+3` |
| FQDN | `domainname: bigtop.apache.org` + the service name, plus a bind-mounted `/etc/hosts` |
| Package delivery | A shared host directory `./ambari-repo` mounted at `/var/repo/ambari` in every container |
| Memory | `mem_limit: 8g`, `mem_swappiness: 0` per container |

## 2. `/etc/hosts`

Upstream generates a hosts file and bind-mounts it into every container:

```
172.20.0.2  bigtop_hostname0
172.20.0.3  bigtop_hostname1
172.20.0.4  bigtop_hostname2
172.20.0.5  bigtop_hostname3
```

## 3. SSH

> "SSH setup is required for Ambari to function properly."

Per container: `ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa`, `systemctl enable --now sshd`. The
server's public key is then appended to each agent's `authorized_keys`, and connectivity is
tested with `ssh -o StrictHostKeyChecking=no`.

## 4. Host preparation (run in every container)

```bash
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
systemctl stop firewalld && systemctl disable firewalld

dnf install -y sudo openssh-server openssh-clients which iproute net-tools less vim-enhanced
dnf install -y initscripts wget curl tar unzip git
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled powertools
dnf update -y
```

The **Rocky-Devel** repository must also be enabled (`/etc/yum.repos.d/Rocky-Devel.repo`:
uncomment, or set `enabled=1`).

## 5. Packages and the local repository

Official download locations — note the domain is **`apache-ambari.com`**, a community-run
site, *not* an `apache.org` host:

| Artefact | URL |
|---|---|
| Ambari 3.0.0, Rocky 8 | `https://apache-ambari.com/dist/ambari/3.0.0/rocky8/` |
| Ambari 3.0.0, Rocky 9 | `https://apache-ambari.com/dist/ambari/3.0.0/rocky9/` |
| Bigtop stack 3.3.0, Rocky 8 | `https://apache-ambari.com/dist/bigtop/3.3.0/rocky8/` |
| Bigtop stack 3.3.0, Rocky 9 | `https://apache-ambari.com/dist/bigtop/3.3.0/rocky9/` |

MD5 checksums are published as `MD5SUMS.txt` in each directory.

> ### ⚠ Two statements from that page that shape this whole project
>
> **“All packages are built for x86_64 architecture.”**
>
> **“This site is hosted on a server with limited bandwidth. Please be considerate when
> downloading packages.”**

Mirroring procedure, as published:

```bash
dnf install -y createrepo
mkdir -p /var/www/html/ambari-repo && chmod -R 755 /var/www/html/ambari-repo
cd /var/www/html/ambari-repo
wget -r -np -nH --cut-dirs=4 --reject 'index.html*' https://www.apache-ambari.com/dist/ambari/3.0.0/rocky8/
wget -r -np -nH --cut-dirs=4 --reject 'index.html*' https://www.apache-ambari.com/dist/bigtop/3.3.0/rocky8/
createrepo .
```

Served over nginx with `autoindex on`, and consumed via:

```ini
[ambari]
name=Ambari Repository
baseurl=http://<repo-host>/ambari-repo
gpgcheck=0
enabled=1
```

## 6. Installing Ambari

**Every host:**
```bash
yum install -y python3-distro
yum install -y java-17-openjdk-devel
yum install -y java-1.8.0-openjdk-devel
yum install -y ambari-agent
```

**Server host only:**
```bash
yum install -y python3-psycopg2
yum install -y ambari-server
```

> **Two JDKs are required, deliberately.** Java **17** runs the Ambari server itself; Java
> **8** runs the managed stack. They are passed as separate flags at setup time.

## 7. PostgreSQL and server setup

```bash
yum install -y postgresql
/usr/bin/postgresql-setup --initdb

sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf
cat >> /var/lib/pgsql/data/pg_hba.conf << 'EOF'
host ambari ambari 0.0.0.0/0 md5
host hive hive 0.0.0.0/0 md5
host ranger ranger 0.0.0.0/0 md5
host rangerkms rangerkms 0.0.0.0/0 md5
EOF
```

```sql
CREATE ROLE "ambari" LOGIN PASSWORD 'admin' NOINHERIT;
CREATE DATABASE ambari;
GRANT ALL PRIVILEGES ON DATABASE ambari TO ambari;
```

```bash
PGPASSWORD='admin' psql -h localhost -p 5432 -U ambari -d ambari \
  -f /var/lib/ambari-server/resources/Ambari-DDL-Postgres-CREATE.sql

ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-42.7.3.jar

ambari-server setup -s \
  -j /usr/lib/jvm/java-1.8.0-openjdk \
  --ambari-java-home /usr/lib/jvm/java-17-openjdk \
  --database=postgres --databasehost=localhost --databaseport=5432 \
  --databasename=ambari --databaseusername=ambari --databasepassword=admin

ambari-server start
```

The schema DDL ships inside the `ambari-server` package at
`/var/lib/ambari-server/resources/Ambari-DDL-Postgres-CREATE.sql`. MySQL is offered as an
alternative, with `ambari` / `hive` / `ranger` / `rangerkms` databases.

## 8. Agent configuration — **the key finding for decision D-004**

```bash
sed -i "s/hostname=.*/hostname=your_ambari_server_hostname/" /etc/ambari-agent/conf/ambari-agent.ini
ambari-agent start
```

**Agents are pointed at the server by editing one field and started directly.** The SSH-based
host bootstrap wizard is *not* used. This is precisely the mechanism decision D-004 proposed,
confirmed by upstream's own installation guide.

## 9. Ports and access

Ambari Web: `http://<server>:8080`, default credentials `admin` / `admin`.

Upstream's firewall table:

| Component | Ports |
|---|---|
| Ambari Server | 8080 (web), **8440, 8441 (agent communication)** |
| Core Hadoop | 8020, 9000, 50070, 50075 |
| YARN | 8032, 8088, 19888 |
| Hive | 9083, 10000 |

NodeManagers allocate containers on dynamic ports (32768–65535), restrictable via
`yarn.nodemanager.resource.ports`.

Log locations: `/var/log/ambari-server/ambari-server.log`,
`/var/log/ambari-agent/ambari-agent.log`.

## 10. What upstream does *not* cover

Blueprints and the headless REST install are documented on a **separate** Ambari page, not in
this quick-start path. The quick-start assumes a human drives the Ambari Web install wizard
after the agents register. **SPIKE-004 therefore remains open** — the exact repository-version
registration payload and the confirmed stack identifier string for BIGTOP 3.3.0 still have to
be read from a live server.

---

## Appraisal — what this project adopts, and what it does not

Upstream is a **manual runbook**, and this project exists to automate it. Adopting its
mechanisms is right; adopting its ergonomics is not.

### Adopted

- `bigtop/puppet:trunk-rockylinux-8` as the host base image.
- `command: /sbin/init` with `privileged: true`.
- The local package mirror, and every install command in §§ 4–8.
- The dual-JDK requirement (17 for Ambari, 8 for the stack).
- Agent registration by `ambari-agent.ini` `hostname=` — confirming D-004.

### Rejected, with reasons

**1. Underscores in hostnames.** Upstream names its hosts `bigtop_hostname0`. Underscores are
not legal in DNS hostnames (RFC 952 / RFC 1123), and Java's `java.net.URI` rejects them.

This repository's predecessor has **already been bitten by exactly this**. From
`docker-hive/docker-compose.yml`:

```
# solve java.net.URISyntaxException Illegal character in hostname at index 49:
#   thrift://docker-hive-hive-metastore-1.docker-hive_default:9083
networks:
  default:
    name: docker-hive-default
```

The illegal character was the underscore in `docker-hive_default`. Hive's metastore URI on an
upstream-named cluster would be `thrift://bigtop_hostname0.bigtop.apache.org:9083` — the same
exception, in the same component. This project uses **hyphens only**: `master1`, `worker1`.

**2. A hand-written, bind-mounted `/etc/hosts` with hardcoded IPs.** Upstream pins
`172.20.0.2`–`172.20.0.5`, but its Compose file **declares no network with that subnet**, so
the addresses Docker actually assigns need not match. Even when they do, they change when
containers are recreated. This project uses Docker's embedded DNS with network aliases
(failure mode F10) and does not write `/etc/hosts`.

**3. Manual `docker exec` for every step.** Upstream has the reader shell into four containers
and run `dnf install` by hand, then repeat. That is the problem this project solves: those
commands belong in an image build and a provisioning script.

**4. The Ambari Web install wizard.** Upstream's quick-start ends at the wizard. Constitution
P2 forbids manual steps; this project drives a blueprint over REST instead.

**5. `version: '3'`.** Obsolete in Compose v2 and now warned about.

**6. Blanket `privileged: true` — adopted, but not silently.** It is upstream's answer and
this project uses it, with the security implication stated in the README rather than buried.
Narrowing it to specific capabilities remains a possible later refinement, not a blocker.

### Where upstream contradicts itself

The quick-start guide describes the Docker environment as "one server and two agents"; the
Compose file in the Docker setup guide defines **three** agents. Minor, but a reminder that
these pages are community-maintained and worth verifying against behaviour rather than trusting
verbatim.
