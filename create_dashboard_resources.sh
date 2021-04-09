#!/usr/bin/env bash
# Create Grafana workload and services on an existing kuberntes cluster

working_dir=`pwd`
DASHBOARD_NAMESPACE=`awk -F= '/DASHBOARD_NAMESPACE/{ print $2 }' ./kubermeter.properties`

Check If DASHBOARD_NAMESPACE exists

kubectl get namespace $DASHBOARD_NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Grafana services already exist in namespace '$DASHBOARD_NAMESPACE'. You don't need to create another one."
  exit 1
fi

echo "Creating Namespace: $DASHBOARD_NAMESPACE..."
kubectl create namespace $DASHBOARD_NAMESPACE
echo

echo "Creating Influxdb and service..."
kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/kubermeter_influxdb.yaml
echo

echo "Creating Grafana node and services..."
kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/jmeter_grafana.yaml
echo


waiting_msg="Waiting for all pods to be ready.."
iter="0"
max_iter="10"
all_conatiners_ready=false


while [[ "$all_conatiners_ready" = false && $iter -lt $max_iter ]]; do
  
  container_readiness_arr=(`kubectl get pods -n $DASHBOARD_NAMESPACE \
    -o jsonpath='{.items[*].status.containerStatuses[*].ready}'`)
  [[ ${container_readiness_arr[*]} =~ true ]] && all_conatiners_ready=true || all_conatiners_ready=false
  waiting_msg="${waiting_msg}."
  echo -ne "$waiting_msg \r"
  sleep 1
  let "iter++"

done

echo 

if [[ "$all_conatiners_ready" = false && $iter -eq $max_iter ]]; then
  echo "Containers are not ready before timing out. Check the cluster health, or \
use 'kubectl delete ns $DASHBOARD_NAMESPACE' to start over.\n"
  exit 1
fi

echo "Dashboard components are ready."
echo

## Create jmeter database automatically in Influxdb
echo "Creating Database 'jmeter' in influxdb..."
influxdb_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep influxdb-jmeter | awk '{print $1}'`
kubectl exec -ti -n $DASHBOARD_NAMESPACE $influxdb_pod -- influx -execute "CREATE DATABASE jmeter"
echo


## Create the influxdb datasource in Grafana
echo "Creating the data source 'jmeterdb' linking grafana to influxdb ..."
grafana_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep jmeter-grafana | awk '{print $1}'`
kubectl exec -ti -n $DASHBOARD_NAMESPACE $grafana_pod -- curl 'http://admin:admin@127.0.0.1:3000/api/datasources' \
-X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary \
'{"name":"jmeterdb","type":"influxdb","url":"http://kubermeter-influxdb:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}'
echo


