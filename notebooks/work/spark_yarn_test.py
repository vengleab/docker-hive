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
    num_samples = 100000
    def inside(p):
        x, y = random.random(), random.random()
        return x*x + y*y < 1

    count = spark.sparkContext.parallelize(range(0, num_samples)) \
                 .filter(inside).count()
    print(f"Pi is roughly {4.0 * count / num_samples}")

    spark.stop()

if __name__ == "__main__":
    spark_yarn_test()
