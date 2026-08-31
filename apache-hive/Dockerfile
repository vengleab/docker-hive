# Download Stage
FROM alpine AS download
ENV DOWNLOAD_DIR=/tmp
WORKDIR $DOWNLOAD_DIR
ENV HIVE_URL=https://archive.apache.org/dist/hive/hive-4.0.1/apache-hive-4.0.1-bin.tar.gz
ENV PG_JAR_URL=https://jdbc.postgresql.org/download/postgresql-9.4.1212.jar
RUN apk add --no-cache wget && wget -O apache-hive.tar.gz "$HIVE_URL" \
    && wget "$PG_JAR_URL" -O postgresql-jdbc.jar && apk del wget

#================================================================================================================================

FROM vengleab/big-data-hadoop-hive-learning-cluster:base
# Set HIVE_VERSION from arg if provided at build, env if provided at run, or default
# https://docs.docker.com/engine/reference/builder/#using-arg-variables
# https://docs.docker.com/engine/reference/builder/#environment-replacement
ENV HIVE_VERSION=4.0.1
ENV DOWNLOAD_DIR=/tmp
ENV HIVE_HOME=/opt/hive
ENV PATH=$HIVE_HOME/bin:$PATH
# Must match the actual install path from the base image (was pointing at a non-existent
# /opt/hadoop-<version> dir, which broke Hive's launcher scripts under Hive 4.x)
ENV HADOOP_HOME=/opt/hadoop
ENV JAVA_VERSION=17

WORKDIR /opt

COPY --from=download $DOWNLOAD_DIR/apache-hive.tar.gz .
COPY --from=download $DOWNLOAD_DIR/postgresql-jdbc.jar $DOWNLOAD_DIR/postgresql-jdbc.jar

RUN apt-get update && apt-get install -y --no-install-recommends procps && \
    tar -xzf apache-hive.tar.gz && \
    rm apache-hive.tar.gz && \
    rm -rf hive && \
    mv apache-hive-4.0.1-bin hive && \
    rm -rf $HIVE_HOME/examples $HIVE_HOME/doc $HIVE_HOME/*.txt $HIVE_HOME/README.txt $HIVE_HOME/NOTICE.txt $HIVE_HOME/LICENSE $HIVE_HOME/RELEASE_NOTES.txt && \
    mv $DOWNLOAD_DIR/postgresql-jdbc.jar $HIVE_HOME/lib/postgresql-jdbc.jar && \
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#Spark should be compiled with Hive to be able to use it
#hive-site.xml should be copied to $SPARK_HOME/conf folder

COPY conf $HIVE_HOME/conf

COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# solve log version conflict: align hive's bundled guava with hadoop's, regardless of exact versions shipped
RUN rm -f /opt/hive/lib/guava-*.jar && \
    cp /opt/hadoop/share/hadoop/common/lib/guava-*.jar /opt/hive/lib/

EXPOSE 10000
EXPOSE 10002

ENTRYPOINT ["entrypoint.sh"]
CMD ["startup.sh"]
