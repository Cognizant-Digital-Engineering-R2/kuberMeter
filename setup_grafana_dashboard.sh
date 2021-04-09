#!/usr/bin/env bash
# Create a new Jmeter namespace and resources on an existing kuberntes cluster

working_dir=`pwd`

DASHBOARD_NAMESPACE=`awk -F= '/DASHBOARD_NAMESPACE/{ print $2 }' ./kubermeter.properties`


## Create jmeter database automatically in Influxdb

echo "Creating Influxdb jmeter Database..."

influxdb_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep influxdb-jmeter | awk '{print $1}'`

kubectl exec -ti -n $DASHBOARD_NAMESPACE $influxdb_pod -- influx -execute "CREATE DATABASE jmeter"


## Create the influxdb datasource in Grafana

echo "Creating the Influxdb data source..."

grafana_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep jmeter-grafana | awk '{print $1}'`

kubectl exec -ti -n $DASHBOARD_NAMESPACE $grafana_pod -- curl 'http://admin:admin@127.0.0.1:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"jmeterdb","type":"influxdb","url":"http://kubermeter-influxdb:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}'

echo
