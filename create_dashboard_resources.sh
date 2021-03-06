#!/usr/bin/env bash
# Create Grafana workload and services on an existing kuberntes cluster

working_dir=`pwd`
DASHBOARD_NAMESPACE=`awk -F= '/DASHBOARD_NAMESPACE/{ print $2 }' ./kubermeter.properties`
DASHBOARD_PODS_PREFIX=`awk -F= '/DASHBOARD_PODS_PREFIX/{ print $2 }' ./kubermeter.properties`
DASHBOARD_GRAFANA=`awk -F= '/DASHBOARD_GRAFANA/{ print $2 }' ./kubermeter.properties`
DASHBOARD_FRONTEND=`awk -F= '/DASHBOARD_FRONTEND/{ print $2 }' ./kubermeter.properties`
DASHBOARD_INFLUXDB=`awk -F= '/DASHBOARD_INFLUXDB/{ print $2 }' ./kubermeter.properties`

# Check If DASHBOARD_NAMESPACE already exists
kubectl get namespace $DASHBOARD_NAMESPACE > /dev/null 2>&1

if [ $? -eq 0 ]
then
  echo "Grafana services already exist in namespace '$DASHBOARD_NAMESPACE'. You don't need to create another one."
  exit 1
fi

echo "Creating Namespace: $DASHBOARD_NAMESPACE..."
kubectl create namespace $DASHBOARD_NAMESPACE
echo

echo "Creating InfluxDB deployment and service..."
kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/dashboard_influxdb.yaml
echo

echo "Creating Grafana deployment and service..."
kubectl create -n $DASHBOARD_NAMESPACE -f $working_dir/dashboard_grafana.yaml
echo


# Wait for all pods to be ready
echo "Waiting for all pods to be ready..."
wait_time_elapsed="0"
wait_time_interval="5"
wait_time_min="30"
wait_time_max="180"
start_time=$(date +%s)
all_conatiners_ready=false
ip_pat='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
NUM_PODS="2" # Grafana and InfluxDB

while [[ "$all_conatiners_ready" = false ]]; do
  
  sleep $wait_time_interval

  now=$(date +%s)
  wait_time_elapsed=$(($now - $start_time))

  if [[ $wait_time_elapsed -ge $wait_time_max ]]; then
    echo "Containers are not ready within the limit of $wait_time_max seconds. Check the cluster health, \
and/or use 'kubectl delete ns $DASHBOARD_NAMESPACE' to start over.\n"
    exit 1
  elif [[ $wait_time_elapsed -ge $wait_time_min ]]; then
    num_pod_ips=`kubectl -n $DASHBOARD_NAMESPACE get pods -o wide | grep $DASHBOARD_PODS_PREFIX | awk '{print $6}' | grep -Ec $ip_pat`
    [[ "$num_pod_ips" -eq $(($NUM_PODS)) ]] && all_conatiners_ready=true || all_conatiners_ready=false
    kubectl -n $DASHBOARD_NAMESPACE get pods -o wide
  fi

done

echo 
echo "Dashboard components are ready."
echo


# Create jmeter database automatically in Influxdb
echo "Creating Database 'jmeter' in influxdb..."
influxdb_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep $DASHBOARD_INFLUXDB | awk '{print $1}'`
kubectl exec -ti -n $DASHBOARD_NAMESPACE $influxdb_pod -- influx -execute "CREATE DATABASE jmeter"
echo


# Create the influxdb datasource in Grafana
echo "Creating the data source 'jmeterdb' linking grafana to influxdb ..."
grafana_pod=`kubectl get po -n $DASHBOARD_NAMESPACE | grep $DASHBOARD_GRAFANA | awk '{print $1}'`
kubectl exec -ti -n $DASHBOARD_NAMESPACE $grafana_pod -- curl 'http://admin:admin@127.0.0.1:3000/api/datasources' \
-X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary \
'{"name":"jmeterdb","type":"influxdb","url":"http://kubermeter-influxdb:8086","access":"proxy","isDefault":true,"database":"jmeter","user":"admin","password":"admin"}'
echo


# "Wait for Grafana front-end external IP allocation
waiting_msg="Waiting for Grafana front-end external IP allocation..."
wait_time_elapsed="0"
wait_time_interval="5"
wait_time_min="5"
wait_time_max="120"
start_time=$(date +%s)
grafana_front_end_ip='<pending>'

while [[ "$grafana_front_end_ip" = '<pending>' ]]; do
  
  waiting_msg="${waiting_msg}."
  echo -ne "$waiting_msg \r"
  sleep $wait_time_interval
  now=$(date +%s)
  wait_time_elapsed=$(($now - $start_time))

  if [[ $wait_time_elapsed -ge $wait_time_max ]]; then
    echo "Grafana front-end external IP is not allocated within the limit of $wait_time_max seconds. Check the cluster health, \
and/or use 'kubectl delete ns $DASHBOARD_NAMESPACE' to start over.\n"
    exit 1
  elif [[ $wait_time_elapsed -ge $wait_time_min ]]; then
    grafana_front_end_ip=`kubectl get svc -n $DASHBOARD_NAMESPACE | grep $DASHBOARD_FRONTEND | awk '{print $4}'`
  fi

done

echo
echo "Dashboard resources created. Access http://$grafana_front_end_ip from a browser to import the 'kubermeter-dashboard.json'. \
Select 'jmeterdb' for Data source."
