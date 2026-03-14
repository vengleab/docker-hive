#!/bin/bash

# This script submits the spark_yarn_test.py to the YARN cluster.
# It assumes you are running this from within a container that has spark-submit 
# and access to the YARN configuration.

SCRIPT_PATH="/home/jovyan/work/spark_yarn_test.py"
spark-submit \
    --master yarn \
    --deploy-mode client \
    --name "Spark YARN Test Task" \
    --conf spark.executor.memory=1g \
    --conf spark.executor.cores=1 \
    --conf spark.dynamicAllocation.enabled=false \
    "$SCRIPT_PATH"