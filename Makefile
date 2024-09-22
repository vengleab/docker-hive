start:
	docker compose up -d

stop: 
	docker compose stop

cleanup:
	docker compose down -v

build: build-hadoop-base build-hive

build-hadoop-base:
	docker build -t vengleab/docker-hive:base ./hadoop-cluster/base

build-hive:
	docker build -t vengleab/docker-hive:hive ./
