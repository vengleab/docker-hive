start:
	docker compose up -d

stop: 
	docker compose stop

cleanup:
	docker compose down -v

# New buildx commands for multi-platform builds
buildx-init:
	docker buildx create --name multiarch --use || true

buildx: buildx-init buildx-hadoop-base buildx-hive buildx-namenode buildx-datanode buildx-historyserver buildx-nodemanager buildx-resourcemanager buildx-hive-metastore buildx-hive-metastore-postgresql

buildx-hadoop-base:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:base \
		--push \
		./hadoop-cluster/base

buildx-hive:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hive \
		--push \
		./

# New buildx commands for additional services
buildx-namenode:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hadoop-namenode \
		--push \
		./hadoop-cluster/namenode

buildx-datanode:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hadoop-datanode \
		--push \
		./hadoop-cluster/datanode

buildx-historyserver:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hadoop-historyserver \
		--push \
		./hadoop-cluster/historyserver

buildx-nodemanager:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hadoop-nodemanager \
		--push \
		./hadoop-cluster/nodemanager

buildx-resourcemanager:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hadoop-resourcemanager \
		--push \
		./hadoop-cluster/resourcemanager

buildx-hive-metastore:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hive-metastore \
		--push \
		./

buildx-hive-metastore-postgresql:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:hive-metastore-postgresql \
		--push \
		./docker-hive-metastore-postgresql

buildx-spark-notebook:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t vengleab/docker-hive-multi:spark-notebook \
		--push \
		./notebooks
