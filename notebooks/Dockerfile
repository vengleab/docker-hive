
ARG SPARK_VERSION=3.5.5

# Download extra JARs
FROM alpine AS download
WORKDIR /tmp
RUN wget -q https://repo1.maven.org/maven2/software/amazon/awssdk/s3/2.20.152/s3-2.20.152.jar \
    && wget -q https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk/1.12.367/aws-java-sdk-1.12.367.jar \
    && wget -q https://repo1.maven.org/maven2/io/delta/delta-core_2.12/2.4.0/delta-core_2.12-2.4.0.jar \
    && wget -q https://repo1.maven.org/maven2/io/delta/delta-storage/2.4.0/delta-storage-2.4.0.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/kafka/kafka-clients/3.4.1/kafka-clients-3.4.1.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-sql-kafka-0-10_2.12/3.4.1/spark-sql-kafka-0-10_2.12-3.4.1.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-streaming-kafka-0-10-assembly_2.12/3.4.1/spark-streaming-kafka-0-10-assembly_2.12-3.4.1.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/commons/commons-pool2/2.11.1/commons-pool2-2.11.1.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/spark/spark-token-provider-kafka-0-10_2.12/3.4.1/spark-token-provider-kafka-0-10_2.12-3.4.1.jar \
    && wget -q https://repo1.maven.org/maven2/org/postgresql/postgresql/42.6.0/postgresql-42.6.0.jar \
    && wget -q https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.2/hadoop-aws-3.3.2.jar \
    && wget -q https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar

FROM apache/spark:${SPARK_VERSION}-scala2.12-java11-python3-r-ubuntu
ARG SPARK_VERSION
USER root

ENV SPARK_HOME=/usr/local/spark \
    PYSPARK_PYTHON=/usr/bin/python3.9 \
    PYSPARK_DRIVER_PYTHON=/usr/bin/python3.9 \
    PYTHONPATH=/opt/spark/python:/opt/spark/python/lib/pyspark.zip:/opt/spark/python/lib/py4j-0.10.9.7-src.zip \
    PATH="${PATH}:/usr/local/spark/bin:/usr/local/spark/sbin"

# Install Python 3.9, make it the default python3, reinstall pyspark+jupyterlab
# into it, create jovyan user/dirs, and set up before-notebook.d hook directory.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3.9 \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 2 \
    && update-alternatives --set python3 /usr/bin/python3.9 \
    && python3.9 /usr/lib/python3/dist-packages/easy_install.py pip 2>/dev/null || true \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python3.9 \
    && pip3 install --no-cache-dir jupyterlab \
    && useradd -m -s /bin/bash jovyan \
    && mkdir -p /home/jovyan/work /home/jovyan/hadoop-conf /usr/local/bin/before-notebook.d \
    && ln -s /opt/spark /usr/local/spark \
    && rm -rf /root/.cache/pip

COPY --from=download /tmp/*.jar /opt/spark/jars/

WORKDIR /home/jovyan/work
EXPOSE 8888

CMD ["/bin/bash", "-c", \
    "for f in /usr/local/bin/before-notebook.d/*.sh; do [ -f \"$f\" ] && bash \"$f\"; done; \
     exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root --notebook-dir=/home/jovyan/work"]
