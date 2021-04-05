#!/usr/bin/env bash
#Create multiple Jmeter namespaces on an existing kuberntes cluster
#Started On January 23, 2018

working_dir=`pwd`

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

tenant="$1"
if [ -z "$tenant" ]
then
  echo "Enter the name of the new tenant unique name, this will be used to create the namespace"
  read tenant
fi

echo

#Check If namespace exists

kubectl get namespace $tenant > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Namespace $tenant already exists, please select a unique name"
  echo "Current list of namespaces on the kubernetes cluster"
  sleep 2

 kubectl get namespaces | grep -v NAME | awk '{print $1}'
  exit 1
fi

echo
echo "Creating Namespace: $tenant"

kubectl create namespace $tenant

echo "Namspace $tenant has been created"

echo

echo "Creating Jmeter slave nodes"

nodes=`kubectl get no | egrep -v "master|NAME" | wc -l`

echo

echo "Number of worker nodes on this cluster is " $nodes

echo

echo "Creating Jmeter slave replicas and service"

kubectl create -n $tenant -f $working_dir/jmeter_slaves.yaml

echo "Creating Jmeter Master"

kubectl create -n $tenant -f $working_dir/jmeter_master.yaml

echo "Creating Influxdb and service"

kubectl create -n $tenant -f $working_dir/jmeter_influxdb.yaml

echo "Creating Grafana Deployment"

kubectl create -n $tenant -f $working_dir/jmeter_grafana.yaml

echo "Printout Of the $tenant Objects"

echo

kubectl get -n $tenant all

echo namespace = $tenant > $working_dir/tenant_export
