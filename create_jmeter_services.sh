#!/usr/bin/env bash
# Create a new Jmeter namespace and resources on an existing kuberntes cluster
#Started On January 23, 2018

working_dir=`pwd`
JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`

echo "Current list of namespaces on the kubernetes cluster:"

echo

kubectl get namespaces | grep -v NAME | awk '{print $1}'

echo

echo -n "Create a new namespace for the JMeter resources: $JMETER_NAMESPACE_PREFIX"
read ns_input
echo -n "How many JMeter slaves do you want to use? "
read slave_num


jmeter_namespace="$JMETER_NAMESPACE_PREFIX$ns_input"
echo $jmeter_namespace
echo $slave_num


echo

#Check If namespace exists

kubectl get namespace $jmeter_namespace > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Namespace $jmeter_namespace already exists, please select a unique name"
  echo "Current list of namespaces on the kubernetes cluster"
  sleep 2

 kubectl get namespaces | grep -v NAME | awk '{print $1}'
  exit 1
fi

echo
echo "Creating Namespace: $jmeter_namespace"

kubectl create namespace $jmeter_namespace

echo "Namspace $jmeter_namespace has been created"

exit

echo

echo "Creating Jmeter slave nodes"

nodes=`kubectl get no | egrep -v "master|NAME" | wc -l`

echo

echo "Number of worker nodes on this cluster is " $nodes

echo

echo "Creating Jmeter slave replicas and service"

kubectl create -n $jmeter_namespace -f $working_dir/jmeter_slaves.yaml

echo "Creating Jmeter master"

kubectl create -n $jmeter_namespace -f $working_dir/jmeter_master.yaml

echo "Printout Of the $jmeter_namespace Objects"

echo

kubectl get -n $jmeter_namespace all

echo namespace = $jmeter_namespace > $working_dir/tenant_export
