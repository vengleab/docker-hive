start:
	docker compose up -d

stop: 
	docker compose stop

cleanup:
	docker compose down -v

build: build-hadoop-base build-hive
build-arm: build-hadoop-base-arm build-hive-arm

build-hadoop-base:
	docker build -t vengleab/docker-hive:base ./hadoop-cluster/base

build-hive:
	docker build -t vengleab/docker-hive:hive ./

build-hadoop-base-arm:
	docker build -t vengleab/docker-hive-arm:base ./hadoop-cluster/base

build-hive-arm:
	docker build -t vengleab/docker-hive-arm:hive ./
