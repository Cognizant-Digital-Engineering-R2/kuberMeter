#!/bin/bash -e
docker system prune -a

docker build --tag="kubermeter/jmeter-base:latest" -f jmeter-base.dockerfile .
docker build --tag="kubermeter/jmeter-master:latest" -f jmeter-master.dockerfile .
docker build --tag="kubermeter/jmeter-slave:latest" -f jmeter-slave.dockerfile .
