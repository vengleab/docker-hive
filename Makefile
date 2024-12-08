ENV_FILE := hadoop-hive.env
JAVA_HOME_AMD := /usr/lib/jvm/java-8-openjdk-amd64/
JAVA_HOME_ARM := /usr/lib/jvm/java-8-openjdk-arm64/

update-env:
	@if grep -q "^JAVA_HOME=" $(ENV_FILE); then \
	    sed -i "s|^JAVA_HOME=.*|JAVA_HOME=$(JAVA_HOME_AMD)|" $(ENV_FILE); \
	else \
	    echo "JAVA_HOME=$(JAVA_HOME_AMD)" >> $(ENV_FILE); \
	fi

update-arm-env:
	@if grep -q "^JAVA_HOME=" $(ENV_FILE); then \
	    sed -i "s|^JAVA_HOME=.*|JAVA_HOME=$(JAVA_HOME_ARM)|" $(ENV_FILE); \
	else \
	    echo "JAVA_HOME=$(JAVA_HOME_ARM)" >> $(ENV_FILE); \
	fi



start: update-env
	docker compose up -d

start-arm: update-arm-env
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
	docker build -t vengleab/docker-hive-arm:base ./hadoop-cluster/base-arm

build-hive-arm:
	docker build -t vengleab/docker-hive-arm:hive ./ -f Dockerfile.ARM
