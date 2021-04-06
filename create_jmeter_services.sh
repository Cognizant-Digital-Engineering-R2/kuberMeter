#!/usr/bin/env bash
#Create multiple Jmeter namespaces on an existing kuberntes cluster
#Started On January 23, 2018

working_dir=`pwd`
JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`

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

echo "Creating Jmeter master"

kubectl create -n $tenant -f $working_dir/jmeter_master.yaml

echo "Printout Of the $tenant Objects"

echo

kubectl get -n $tenant all

echo namespace = $tenant > $working_dir/tenant_export
