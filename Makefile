start:
	docker compose up -d

start-arm:
	docker compose -f docker-compose-arm.yml up -d

stop-arm:
	docker compose -f docker-compose-arm.yml stop

cleanup-arm:
	docker compose -f docker-compose-arm.yml down -v

stop: 
	docker compose stop

cleanup:
	docker compose down -v

build: build-hadoop-base build-hive
	docker compose build

build-arm: build-hadoop-base-arm build-hive-arm
	docker compose -f docker-compose-arm.yml build

build-hadoop-base:
	docker build -t vengleab/docker-hive:base ./hadoop-cluster/base

build-hive:
	docker build -t vengleab/docker-hive:hive ./

build-hadoop-base-arm:
	docker build -t vengleab/docker-hive-arm:base ./hadoop-cluster/base

build-hive-arm:
	docker build -t vengleab/docker-hive-arm:hive ./
