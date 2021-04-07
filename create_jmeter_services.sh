#!/usr/bin/env bash
# Create a new Jmeter namespace and resources on an existing kuberntes cluster

working_dir=`pwd`
JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`

echo "Current list of namespaces on the kubernetes cluster:"

echo

jm_namespaces=`kubectl get namespaces | grep -v NAME | awk '{print $1}' | awk "/$JMETER_NAMESPACE_PREFIX/{print $1}"`

for jmns in $jm_namespaces; do
  echo $jmns
done

echo


while [[ -z "$ns_input" ]]; do
  echo -n "Create a new namespace for the JMeter resources: $JMETER_NAMESPACE_PREFIX"
  read ns_input
  if [ ! -z "$ns_input" ] ; then # If ns_input is not an empty string then
    jmeter_namespace="$JMETER_NAMESPACE_PREFIX$ns_input"
    # Check if the new jmeter_namespace already exists
    for jmns in $jm_namespaces; do
      if [ $jmns == $jmeter_namespace ]; then
        echo "Namespace $jmeter_namespace already exists, please use a unique name."
        ns_input=''
      fi
    done
  fi
done

while [[ "$slave_num" -lt 1 || "$slave_num" -gt 10 ]]; do
  echo -n "How many JMeter slaves do you want to use? (1-10): "
  read slave_num
done


echo

echo "Creating Namespace: $jmeter_namespace"

kubectl create namespace $jmeter_namespace


echo "Creating Jmeter slave replicas and service"

kubectl create -n $jmeter_namespace -f $working_dir/jmeter_slaves.yaml

echo "Creating Jmeter master"

kubectl create -n $jmeter_namespace -f $working_dir/jmeter_master.yaml

echo "Printout Of the $jmeter_namespace Objects"

echo

kubectl get -n $jmeter_namespace all

echo namespace = $jmeter_namespace > $working_dir/tenant_export
