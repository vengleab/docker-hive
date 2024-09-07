current_branch := 3.2.1
build: build-hadoop-base build-hive

build-hadoop-base:
	docker build -t local-hadoop-cluster/bash ./hadoop-cluster/base

build-hive:
	docker build -t local-hive ./
