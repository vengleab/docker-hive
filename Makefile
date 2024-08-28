current_branch := 3.2.1
build:
	docker build -t bde2020/hive:$(current_branch) ./
