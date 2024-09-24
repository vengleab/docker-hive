build: build-hadoop-base build-hive

build-hadoop-base:
	docker build -t vengleab/docker-hive:base ./hadoop-cluster/base

build-hive:
	docker build -t vengleab/docker-hive:hive ./
