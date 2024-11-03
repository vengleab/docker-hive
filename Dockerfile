# Download Stage
FROM alpine as download
ENV DOWNLOAD_DIR /tmp
WORKDIR $DOWNLOAD_DIR
ENV HIVE_URL https://archive.apache.org/dist/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz
RUN wget -O apache-hive.tar.gz "$HIVE_URL" 

FROM alpine as download-pg
ENV DOWNLOAD_DIR /tmp
WORKDIR $DOWNLOAD_DIR
ENV PG_JAR_URL https://jdbc.postgresql.org/download/postgresql-9.4.1212.jar
RUN wget  "$PG_JAR_URL" -O postgresql-jdbc.jar

#================================================================================================================================

FROM vengleab/docker-hive:base
# Set HIVE_VERSION from arg if provided at build, env if provided at run, or default
# https://docs.docker.com/engine/reference/builder/#using-arg-variables
# https://docs.docker.com/engine/reference/builder/#environment-replacement
ENV HIVE_VERSION=${HIVE_VERSION:-3.1.3}
ENV DOWNLOAD_DIR /tmp
ENV HIVE_HOME /opt/hive
ENV PATH $HIVE_HOME/bin:$PATH
ENV HADOOP_HOME /opt/hadoop-$HADOOP_VERSION

WORKDIR /opt

COPY --from=download $DOWNLOAD_DIR/apache-hive.tar.gz .
COPY --from=download-pg $DOWNLOAD_DIR/postgresql-jdbc.jar $HIVE_HOME/lib/postgresql-jdbc.jar
#Install Hive and PostgreSQL JDBC
RUN apt-get update && apt-get install -y wget procps
RUN tar -xzvf apache-hive.tar.gz && \
	rm apache-hive.tar.gz && \
	rm -r hive && \
	mv apache-hive-3.1.3-bin hive
RUN apt-get --purge remove -y wget && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*


#Spark should be compiled with Hive to be able to use it
#hive-site.xml should be copied to $SPARK_HOME/conf folder

#Custom configuration goes here
ADD conf/hive-site.xml $HIVE_HOME/conf
ADD conf/beeline-log4j2.properties $HIVE_HOME/conf
ADD conf/hive-env.sh $HIVE_HOME/conf
ADD conf/hive-exec-log4j2.properties $HIVE_HOME/conf
ADD conf/hive-log4j2.properties $HIVE_HOME/conf
ADD conf/ivysettings.xml $HIVE_HOME/conf
ADD conf/llap-daemon-log4j2.properties $HIVE_HOME/conf

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
CMD startup.sh
