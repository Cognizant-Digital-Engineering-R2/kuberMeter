#!/usr/bin/env bash
# Create Grafana workload and services on an existing kuberntes cluster

working_dir=`pwd`
DASHBOARD_NAMESPACE=`awk -F= '/DASHBOARD_NAMESPACE/{ print $2 }' ./kubermeter.properties`

#Check If DASHBOARD_NAMESPACE exists

kubectl get namespace $DASHBOARD_NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Grafana services already exist in namespace '$DASHBOARD_NAMESPACE'. You don't need to create another one."
  exit 1
fi

echo
echo "Creating Namespace: $DASHBOARD_NAMESPACE..."

kubectl create namespace $DASHBOARD_NAMESPACE

echo

echo "Creating Influxdb and service..."

kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/jmeter_influxdb.yaml

echo "Creating Grafana node and services..."

kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/jmeter_grafana.yaml

echo "Printout Of the $DASHBOARD_NAMESPACE Objects..."

echo

kubectl get -n $DASHBOARD_NAMESPACE all
