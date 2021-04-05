#!/bin/bash -e
docker system prune -a

# start a local Docker registry
docker run -d -p 5000:5000 --name registry registry:2

DOCKER_REGISTRY='localhost:5000'

docker build --tag="$DOCKER_REGISTRY/kubermeter/jmeter-base:latest" -f jmeter-base.dockerfile .
docker push $DOCKER_REGISTRY/kubermeter/jmeter-base:latest

docker build --tag="$DOCKER_REGISTRY/kubermeter/jmeter-master:latest" -f jmeter-master.dockerfile .
docker push $DOCKER_REGISTRY/kubermeter/jmeter-master:latest

docker build --tag="$DOCKER_REGISTRY/kubermeter/jmeter-slave:latest" -f jmeter-slave.dockerfile .
docker push $DOCKER_REGISTRY/kubermeter/jmeter-slave:latest
