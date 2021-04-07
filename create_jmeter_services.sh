#!/usr/bin/env bash
# Create a new Jmeter namespace and resources on an existing kuberntes cluster

working_dir=`pwd`
JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`

echo "Current list of namespaces on the kubernetes cluster:"

echo

jm_namespaces=`kubectl get namespaces | grep -v NAME | awk '{print $1}' | awk "/$JMETER_NAMESPACE_PREFIX/{print $1}"`

echo $jm_namespaces

echo

jmns_arr=$($jm_namespaces)

# for [ $jmns in ($jm_namespaces) ]

for jmns in $jm_namespaces; do
  echo $jmns
done


exit


while [[ -z "$ns_input" ]]; do
  echo -n "Create a new namespace for the JMeter resources: $JMETER_NAMESPACE_PREFIX"
  read ns_input

#   if [ $? -eq 0 ]; then
#   echo "Namespace $jmeter_namespace already exists, please select a unique name"
#   echo "Current list of namespaces on the kubernetes cluster"
#   sleep 2

#   kubectl get namespaces | grep -v NAME | awk '{print $1}'
#   exit 1
# fi

done


while [[ "$slave_num" -lt 1 || "$slave_num" -gt 10 ]]; do
  echo "in while $slave_num"
  echo -n "How many JMeter slaves do you want to use? (1-10): "
  read slave_num
done


jmeter_namespace="$JMETER_NAMESPACE_PREFIX$ns_input"
echo $jmeter_namespace

exit

echo

#Check If namespace exists

kubectl get namespace $jmeter_namespace > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "Namespace $jmeter_namespace already exists, please select a unique name"
  echo "Current list of namespaces on the kubernetes cluster"
  sleep 2

  kubectl get namespaces | grep -v NAME | awk '{print $1}'
  exit 1
fi

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
