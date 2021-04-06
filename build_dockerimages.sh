#!/bin/bash -e
# Docker hub account hs888555 (bluehao85@gmail.com)
DOCKER_REGISTRY='hs888555'

docker build --tag="kubermeter/jmeter-base:latest" -f jmeter-base.dockerfile .

docker build --tag="$DOCKER_REGISTRY/kubermeter-jmeter-master:latest" -f jmeter-master.dockerfile .
docker push $DOCKER_REGISTRY/kubermeter-jmeter-master:latest

docker build --tag="$DOCKER_REGISTRY/kubermeter-jmeter-slave:latest" -f jmeter-slave.dockerfile .
docker push $DOCKER_REGISTRY/kubermeter-jmeter-slave:latest
