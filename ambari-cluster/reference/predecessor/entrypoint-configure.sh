#!/bin/bash
# ============================================================================
# PREDECESSOR REFERENCE — verbatim excerpt, NOT executed by this project.
#
# Source: docker-hive @ b2da7c2, hadoop-cluster/base/entrypoint.sh (lines 1-60)
#
# This is the configuration mechanism this project REPLACES. It is kept here
# because the migration tool (feature 001, T014 / FR-017) must decode the
# encoding it defines, and because constitution P1 forbids reintroducing it.
#
# THE ENCODING the migration tool must reverse, in this exact order:
#     ___  ->  -       (three underscores become a hyphen)
#     __   ->  _       (two become a literal underscore)
#     _    ->  .       (one becomes a dot)
#
# The perl below achieves that ordering with an @ placeholder so the second
# rule's output is not eaten by the third:
#     s/___/-/g; s/__/@/g; s/_/./g; s/@/_/g;
#
# Worked example:
#     YARN_CONF_yarn_log___aggregation___enable
#       -> strip prefix   yarn_log___aggregation___enable
#       -> apply          yarn.log-aggregation-enable
#
# ---------------------------------------------------------------------------
# ⚠ THREE DRIFTED COPIES EXIST IN THE PREDECESSOR. Only this one is correct.
#
#   hadoop-cluster/base/entrypoint.sh   s/___/-/g; s/__/@/g; s/_/./g; s/@/_/g;   ✔ correct
#   apache-hive/entrypoint.sh           s/___/-/g; s/__/_/g;  s/_/./g;           ✘ wrong
#   notebooks/hadoop-config.sh          s/___/-/g; s/__/_/g;  s/_/./g;           ✘ wrong
#
# The two wrong variants collapse `__` to `_` and then immediately turn that
# `_` into `.`, so any property containing a literal underscore is corrupted.
# The migration tool must implement the CORRECT ordering, and its tests should
# include a property exercising the `__` case to prove it.
#
# This triplication is the concrete argument for constitution P1: the same
# logic copied three times drifted twice, silently.
# ============================================================================

function addProperty() {
  local path=$1
  local name=$2
  local value=$3

  local entry="<property><name>$name</name><value>${value}</value></property>"
  local escapedEntry=$(echo $entry | sed 's/\//\\\//g')
  sed -i "/<\/configuration>/ s/.*/${escapedEntry}\n&/" $path
}

function configure() {
    local path=$1
    local module=$2
    local envPrefix=$3

    local var
    local value

    echo "Configuring $module"
    for c in `printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix=$envPrefix`; do
        name=`echo ${c} | perl -pe 's/___/-/g; s/__/@/g; s/_/./g; s/@/_/g;'`
        var="${envPrefix}_${c}"
        value=${!var}
        echo " - Setting $name=$value"
        addProperty $path $name "$value"
    done
}

# The prefix -> file mapping the migration tool must reproduce:
configure /etc/hadoop/core-site.xml   core   CORE_CONF
configure /etc/hadoop/hdfs-site.xml   hdfs   HDFS_CONF
configure /etc/hadoop/yarn-site.xml   yarn   YARN_CONF
configure /etc/hadoop/httpfs-site.xml httpfs HTTPFS_CONF
configure /etc/hadoop/kms-site.xml    kms    KMS_CONF
configure /etc/hadoop/mapred-site.xml mapred MAPRED_CONF
# and, from apache-hive/entrypoint.sh:
# configure /opt/hive/conf/hive-site.xml hive HIVE_SITE_CONF

# ---------------------------------------------------------------------------
# MULTIHOMED_NETWORK=1 is set in the predecessor's base image, so these are
# always applied. They are bind-address workarounds for running daemons in
# containers. Ambari sets bind hosts itself, so these are NOT migrated —
# recorded here only so the migration table can account for them (FR-018).
# ---------------------------------------------------------------------------
if [ "$MULTIHOMED_NETWORK" = "1" ]; then
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.rpc-bind-host 0.0.0.0
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.servicerpc-bind-host 0.0.0.0
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.http-bind-host 0.0.0.0
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-bind-host 0.0.0.0
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.use.datanode.hostname true
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.use.datanode.hostname true
    addProperty /etc/hadoop/yarn-site.xml yarn.resourcemanager.bind-host 0.0.0.0
    addProperty /etc/hadoop/yarn-site.xml yarn.nodemanager.bind-host 0.0.0.0
    addProperty /etc/hadoop/yarn-site.xml yarn.timeline-service.bind-host 0.0.0.0
    addProperty /etc/hadoop/mapred-site.xml yarn.nodemanager.bind-host 0.0.0.0
fi
