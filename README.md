# Introduction
This project is just for learning purpose, this was successful run on AMD container

# docker-hive

This is a docker container for Apache Hive is based on 
- https://github.com/big-data-europe/docker-hadoop
- https://github.com/big-data-europe/docker-hive/



# Run the project
### Intel or AMD Chip
```bash
make start
```

### ARM Chip ( Mac M1 up)
```bash
make start-arm
```

# To rebuild this project
### Intel or AMD Chip
```bash
make build
```

### ARM Chip ( Mac M1 up)
```bash
make build-arm
```

# Older version:
For using older version, please use prefix `-hadoop-3.2.1-amd-only` in docker-compose.yml
```bash
vengleab/docker-hive:hadoop-namenode-hadoop-3.2.1-amd-only
vengleab/docker-hive:hadoop-datanode-hadoop-3.2.1-amd-only
vengleab/docker-hive:hadoop-historyserver-hadoop-3.2.1-amd-only
vengleab/docker-hive:hadoop-nodemanager-hadoop-3.2.1-amd-only
vengleab/docker-hive:hadoop-resourcemanager-hadoop-3.2.1-amd-only
vengleab/docker-hive:hive-hadoop-3.2.1-amd-only
vengleab/docker-hive:hive-metastore-postgresql-hadoop-3.2.1-amd-only

```