#!/usr/bin/env bash
# Create Grafana workload and services on an existing kuberntes cluster

working_dir=`pwd`
GRAFANA_NAMESPACE=`awk -F= '/GRAFANA_NAMESPACE/{ print $2 }' ./kubermeter.properties`

#Check If GRAFANA_NAMESPACE exists

kubectl get namespace $GRAFANA_NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Grafana services already exist in namespace '$GRAFANA_NAMESPACE'. You don't need to create another one."
  exit 1
fi

echo
echo "Creating Namespace: $GRAFANA_NAMESPACE..."

kubectl create namespace $GRAFANA_NAMESPACE

echo "Namspace $GRAFANA_NAMESPACE has been created."

echo

echo "Creating Influxdb and service..."

kubectl create -n $GRAFANA_NAMESPACE -f $working_dir/jmeter_influxdb.yaml

echo "Creating Grafana node and services..."

kubectl create -n $GRAFANA_NAMESPACE -f $working_dir/jmeter_grafana.yaml

echo "Printout Of the $GRAFANA_NAMESPACE Objects..."

echo

kubectl get -n $GRAFANA_NAMESPACE all
