#!/bin/bash
# Generate Hadoop XML config files from environment variables.
# Uses the same addProperty/configure pattern as hadoop-cluster/base/entrypoint.sh.

HADOOP_CONF_DIR=${HADOOP_CONF_DIR:-/home/jovyan/hadoop-conf}
mkdir -p "$HADOOP_CONF_DIR"

for conf in core-site.xml hdfs-site.xml yarn-site.xml mapred-site.xml; do
    cat > "$HADOOP_CONF_DIR/$conf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
</configuration>
EOF
done

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

    echo "Configuring $module"
    for c in $(printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix=$envPrefix); do
        name=$(echo ${c} | perl -pe 's/___/-/g; s/__/_/g; s/_/./g')
        var="${envPrefix}_${c}"
        value=${!var}
        echo " - Setting $name=$value"
        addProperty $path $name "$value"
    done
}

configure "$HADOOP_CONF_DIR/core-site.xml"    core    CORE_CONF
configure "$HADOOP_CONF_DIR/hdfs-site.xml"    hdfs    HDFS_CONF
configure "$HADOOP_CONF_DIR/yarn-site.xml"    yarn    YARN_CONF
configure "$HADOOP_CONF_DIR/mapred-site.xml"  mapred  MAPRED_CONF

chmod -R a+r "$HADOOP_CONF_DIR"
echo "Hadoop config written to $HADOOP_CONF_DIR"

# Ensure python3.9 is available on the driver to match the executor (nodemanager) Python version
if ! command -v python3.9 &>/dev/null; then
    echo "Installing python3.9 for PySpark driver/executor version alignment..."
    apt-get install -y -q python3.9 python3.9-distutils 2>/dev/null || true
fi
