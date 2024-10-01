# Download Stage
FROM alpine as download
ENV DOWNLOAD_DIR /tmp
ENV HADOOP_VERSION 3.3.6
WORKDIR $DOWNLOAD_DIR
# ENV HADOOP_URL https://archive.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz (amd)
ENV HADOOP_URL https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION-aarch64.tar.gz
RUN wget  "$HADOOP_URL" -O hadoop.tar.gz \
    && wget  "$HADOOP_URL.asc" -O hadoop.tar.gz.asc 

#================================================================================================================================
    
FROM ubuntu:20.04
ENV DOWNLOAD_DIR /tmp
ENV HADOOP_VERSION 3.3.6

RUN apt-get update -y && apt-get install -y --no-install-recommends \
      openjdk-8-jdk \
      net-tools \
      curl \
      netcat-traditional \
      gnupg \
      libsnappy-dev \
    && rm -rf /var/lib/apt/lists/*
      
ENV JAVA_HOME=/usr/lib/jvm/java-8-openjdk-arm64/

RUN curl -O https://dist.apache.org/repos/dist/release/hadoop/common/KEYS

RUN gpg --import KEYS
COPY --from=download $DOWNLOAD_DIR/hadoop.tar.gz.asc $DOWNLOAD_DIR
COPY --from=download $DOWNLOAD_DIR/hadoop.tar.gz $DOWNLOAD_DIR

RUN set -x \
    && gpg --verify $DOWNLOAD_DIR/hadoop.tar.gz.asc \
    && tar -xvf $DOWNLOAD_DIR/hadoop.tar.gz -C /opt/ \
    && rm $DOWNLOAD_DIR/hadoop.tar.gz*

RUN ln -s /opt/hadoop-$HADOOP_VERSION/etc/hadoop /etc/hadoop

RUN mkdir /opt/hadoop-$HADOOP_VERSION/logs

RUN mkdir /hadoop-data

ENV HADOOP_HOME=/opt/hadoop-$HADOOP_VERSION
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV MULTIHOMED_NETWORK=1
ENV USER=root
ENV PATH $HADOOP_HOME/bin/:$PATH

ADD entrypoint.sh /entrypoint.sh

RUN chmod a+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
