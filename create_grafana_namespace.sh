#!/usr/bin/env bash
# Create a Grafana namespace on an existing kuberntes cluster

working_dir=`pwd`
GRAFANA_NAMESPACE=`awk -F= '/GRAFANA_NAMESPACE/{ print $2 }' ./kubermeter.properties`

if ! hash kubectl 2>/dev/null
then
  echo "'kubectl' was not found in PATH"
  echo "Kindly ensure that you can acces an existing kubernetes cluster via kubectl"
  exit
fi

#Check If GRAFANA_NAMESPACE exists

kubectl get namespace $GRAFANA_NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Namespace '$GRAFANA_NAMESPACE' already exists. You don't need to create another one."
  exit 1
fi

echo
echo "Creating Namespace: $GRAFANA_NAMESPACE"

kubectl create namespace $GRAFANA_NAMESPACE

echo "Namspace $GRAFANA_NAMESPACE has been created"

echo

echo "Creating Influxdb and service"

kubectl create -n $GRAFANA_NAMESPACE -f $working_dir/jmeter_influxdb.yaml

echo "Creating Grafana Deployment"

kubectl create -n $GRAFANA_NAMESPACE -f $working_dir/jmeter_grafana.yaml

echo "Printout Of the $GRAFANA_NAMESPACE Objects"

echo

kubectl get -n $GRAFANA_NAMESPACE all

