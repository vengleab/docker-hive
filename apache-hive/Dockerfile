# Download Stage
FROM alpine AS download
ENV DOWNLOAD_DIR=/tmp
WORKDIR $DOWNLOAD_DIR
ENV HIVE_URL=https://archive.apache.org/dist/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz
ENV PG_JAR_URL=https://jdbc.postgresql.org/download/postgresql-9.4.1212.jar
RUN apk add --no-cache wget && wget -O apache-hive.tar.gz "$HIVE_URL" \
    && wget "$PG_JAR_URL" -O postgresql-jdbc.jar && apk del wget

#================================================================================================================================

FROM vengleab/docker-hive-mini:base
# Set HIVE_VERSION from arg if provided at build, env if provided at run, or default
# https://docs.docker.com/engine/reference/builder/#using-arg-variables
# https://docs.docker.com/engine/reference/builder/#environment-replacement
ENV HIVE_VERSION=3.1.3
ENV DOWNLOAD_DIR=/tmp
ENV HIVE_HOME=/opt/hive
ENV PATH=$HIVE_HOME/bin:$PATH
ENV HADOOP_HOME=/opt/hadoop-$HADOOP_VERSION
ENV JAVA_VERSION=8

WORKDIR /opt

COPY --from=download $DOWNLOAD_DIR/apache-hive.tar.gz .
COPY --from=download $DOWNLOAD_DIR/postgresql-jdbc.jar $HIVE_HOME/lib/postgresql-jdbc.jar

RUN apt-get update && apt-get install -y --no-install-recommends procps && \
    tar -xzf apache-hive.tar.gz && \
    rm apache-hive.tar.gz && \
    rm -rf hive && \
    mv apache-hive-3.1.3-bin hive && \
    rm -rf $HIVE_HOME/examples $HIVE_HOME/doc $HIVE_HOME/*.txt $HIVE_HOME/README.txt $HIVE_HOME/NOTICE.txt $HIVE_HOME/LICENSE $HIVE_HOME/RELEASE_NOTES.txt && \
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

# solve log version conflict
RUN cp /opt/hadoop/share/hadoop/common/lib/guava-27.0-jre.jar /opt/hive/lib/
RUN rm -rf /opt/hive/lib/guava-19.0.jar

EXPOSE 10000
EXPOSE 10002

ENTRYPOINT ["entrypoint.sh"]
CMD ["startup.sh"]
