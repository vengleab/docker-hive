# Download and prepare stage
FROM alpine:3.18 as builder
ENV HADOOP_VERSION=3.3.6
WORKDIR /tmp

# Use ARG to determine architecture-specific URL during build
ARG TARGETARCH
ENV HADOOP_URL=https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz
ENV HADOOP_URL_ARM=https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION-aarch64.tar.gz

# Download, verify, extract and clean up in single layer
RUN apk add --no-cache wget gnupg && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        wget "$HADOOP_URL_ARM" -O hadoop.tar.gz && \
        wget "$HADOOP_URL_ARM.asc" -O hadoop.tar.gz.asc; \
    else \
        wget "$HADOOP_URL" -O hadoop.tar.gz && \
        wget "$HADOOP_URL.asc" -O hadoop.tar.gz.asc; \
    fi && \
    wget -O KEYS https://dist.apache.org/repos/dist/release/hadoop/common/KEYS && \
    gpg --import KEYS && \
    gpg --verify hadoop.tar.gz.asc && \
    tar -xzf hadoop.tar.gz && \
    mv hadoop-$HADOOP_VERSION hadoop && \
    # Remove unnecessary files to reduce size
    rm -rf hadoop/share/doc \
        hadoop/share/hadoop/yarn/test \
        hadoop/share/hadoop/mapreduce/sources \
        hadoop/share/hadoop/hdfs/sources \
        hadoop/share/hadoop/common/sources \
        hadoop/share/hadoop/*/lib-examples \
        hadoop/share/hadoop/*/jdiff \
        KEYS hadoop.tar.gz* ~/.gnupg

#================================================================================================================================
    
# Runtime stage - use Alpine with JRE only
FROM openjdk:8-jre

ENV HADOOP_VERSION=3.3.6
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV MULTIHOMED_NETWORK=1
ENV USER=root
ENV PATH=$HADOOP_HOME/bin/:$PATH

RUN apt-get update -y && apt-get install -y --no-install-recommends \
      net-tools \
      curl \
      netcat-traditional \
      gnupg \
      libsnappy-dev \
    && rm -rf /var/lib/apt/lists/*

# Install minimal runtime dependencies in single layer
# RUN apk add --no-cache \
#     bash \
#     curl \
#     netcat-openbsd \
#     perl \
#     snappy \
#     && rm -rf /var/cache/apk/*

# Copy optimized Hadoop installation
COPY --from=builder /tmp/hadoop /opt/hadoop

# Setup directories and permissions in single layer
RUN mkdir -p /opt/hadoop/logs /hadoop-data && \
    ln -s /opt/hadoop/etc/hadoop /etc/hadoop && \
    # Remove any remaining unnecessary files
    find /opt/hadoop -name "*.cmd" -delete && \
    find /opt/hadoop -name "*.bat" -delete

# Copy and setup entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
