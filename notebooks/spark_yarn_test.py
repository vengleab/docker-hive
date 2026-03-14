from pyspark.sql import SparkSession
import random

def spark_yarn_test():
    spark = SparkSession.builder \
        .appName("Spark YARN Connectivity Test") \
        .config("spark.master", "yarn") \
        .config("spark.submit.deployMode", "client") \
        .enableHiveSupport() \
        .getOrCreate()

    print(f"Spark Version: {spark.version}")
    
    # count = spark.range(100).count()
    # count = spark.sql("SELECT 1").collect()
    # 1. Pi Estimation
    num_samples = 100000
    def inside(p):
        x, y = random.random(), random.random()
        return x*x + y*y < 1

    count = spark.sparkContext.parallelize(range(0, num_samples)) \
                 .filter(inside).count()
    print(f"Pi is roughly {4.0 * count / num_samples}")

    # # 2. Hive Integration Test
    # try:
    #     spark.sql("CREATE DATABASE IF NOT EXISTS test_yarn_db")
    #     spark.sql("USE test_yarn_db")
    #     spark.sql("CREATE TABLE IF NOT EXISTS test_table (id INT, message STRING) USING hive")
    #     spark.sql("INSERT INTO test_table VALUES (1, 'Spark on YARN is working!')")
    #     spark.sql("SELECT * FROM test_table").show()
    # except Exception as e:
    #     print(f"Hive test failed: {e}")

    spark.stop()

if __name__ == "__main__":
    spark_yarn_test()
