
# Download Stage
FROM alpine as download
ENV DOWNLOAD_DIR=/tmp
WORKDIR $DOWNLOAD_DIR
RUN wget https://repo1.maven.org/maven2/software/amazon/awssdk/s3/2.20.152/s3-2.20.152.jar \
    && wget https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk/1.12.367/aws-java-sdk-1.12.367.jar \
    && wget https://repo1.maven.org/maven2/io/delta/delta-core_2.12/2.4.0/delta-core_2.12-2.4.0.jar \
    && wget https://repo1.maven.org/maven2/io/delta/delta-storage/2.4.0/delta-storage-2.4.0.jar \
    && wget https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.4.1/kafka-clients-3.4.1.jar \
    && wget https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.4.1/spark-sql-kafka-0-10_2.12-3.4.1.jar \
    && wget https://repo1.maven.org/maven2/org/apache/spark/spark-streaming-kafka-0-10-assembly_2.12/3.4.1/spark-streaming-kafka-0-10-assembly_2.12-3.4.1.jar \
    && wget https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar \
    && wget https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.4.1/spark-token-provider-kafka-0-10_2.12-3.4.1.jar \
    && wget https://repo1.maven.org/maven2/org/postgresql/postgresql/42.6.0/postgresql-42.6.0.jar \
    && wget https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.2/hadoop-aws-3.3.2.jar \
    && wget https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar

FROM alpine as download-spark
ENV DOWNLOAD_DIR=/tmp
WORKDIR $DOWNLOAD_DIR
RUN wget https://archive.apache.org/dist/spark/spark-3.3.1/spark-3.3.1-bin-hadoop3.tgz \
    && tar zxvf $DOWNLOAD_DIR/spark-3.3.1-bin-hadoop3.tgz \
    && rm -rf $DOWNLOAD_DIR/spark-3.3.1-bin-hadoop3.tgz

FROM jupyter/all-spark-notebook:python-3.8
ENV DOWNLOAD_DIR=/tmp
USER root 

COPY --from=download-spark $DOWNLOAD_DIR/spark-3.3.1-bin-hadoop3 $DOWNLOAD_DIR/spark-3.3.1-bin-hadoop3
RUN cd $DOWNLOAD_DIR \
    && mv spark-3.3.1-bin-hadoop3/ /usr/local/ \
    && rm -rf /usr/local/spark \
    && rm -rf /usr/local/spark-3.3.0-bin-hadoop3 \
    && ln -s /usr/local/spark-3.3.1-bin-hadoop3 /usr/local/spark

COPY --from=download /tmp/*.jar /usr/local/spark/jars