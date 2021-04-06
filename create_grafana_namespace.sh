#!/usr/bin/env bash
#Create a  Jmeter namespaces on an existing kuberntes cluster
#Started On January 23, 2018

working_dir=`pwd`
GRAFANA_NAMESPACE='kubermeter-grafana'

echo "checking if kubectl is present"

if ! hash kubectl 2>/dev/null
then
    echo "'kubectl' was not found in PATH"
    echo "Kindly ensure that you can acces an existing kubernetes cluster via kubectl"
    exit
fi

kubectl version --short

echo "Current list of namespaces on the kubernetes cluster:"

echo

kubectl get namespaces | grep -v NAME | awk '{print $1}'

echo

#Check If namespace exists

kubectl get namespace $GRAFANA_NAMESPACE > /dev/null 2>&1

exit

if [ $? -eq 0 ]
then
  echo "Namespace $GRAFANA_NAMESPACE already exists, please select a unique name"
  echo "Current list of namespaces on the kubernetes cluster"
  sleep 2

 kubectl get namespaces | grep -v NAME | awk '{print $1}'
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

echo namespace = $GRAFANA_NAMESPACE > $working_dir/tenant_export
