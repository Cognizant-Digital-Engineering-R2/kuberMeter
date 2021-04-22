#!/usr/bin/env bash
# https://betterdev.blog/minimal-safe-bash-script-template/

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF

Usage: 

$(basename "${BASH_SOURCE[0]}") [-h] test_plan_repo

test_plan_repo: The test plan repository, which must contain test.jmx and test.properties at surface level.

This script will clone the test repo, create a new JMeter namespace and resources on an existing kuberntes cluster and then launch JMeter test.
It requires that you supply the test plan directory (`test_plan_repo`), which must contain `test.jmx` and `test.properties` at surface level.
The directory may contain additional supporting files, such csv, groovy or sql files.
The entire directory will be copied into the jmeter master and slave pods within the namespace `jmeter_namespace`
After execution, the jmeter test log file (jtl) and an HTML report will be pulled from the jmeter-master pod, 
and then packaged into a zip file using test_report_name, or stored it into a persistent volume (TODO).

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info

EOF
  exit
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ ${#args[@]} -lt 1 ]] && die "Arguments incomplete. Use -h for help."

  return 0
}

parse_params "$@"
test_plan_repo="$1"
TEMP_REPO='temp_repo'
POD_TEST_PLAN_DIR='current_test_plan'
JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`
JMETER_SLAVES_SVC=`awk -F= '/JMETER_SLAVES_SVC/{ print $2 }' ./kubermeter.properties`
JMETER_PODS_PREFIX=`awk -F= '/JMETER_PODS_PREFIX/{ print $2 }' ./kubermeter.properties`
POD_KUBERMETER_DIR='/tmp/kubermeter'
JMX_FILE='test'
PROPERTIES_FILE='test'
test_plan_dir="$script_dir/$POD_TEST_PLAN_DIR"


# Checking yq pacakge availability
if ! hash yq 2>/dev/null; then
  echo "Yaml processcor yq v4.6.3+ required: https://github.com/mikefarah/yq"
  echo "Run 'sudo wget https://github.com/mikefarah/yq/releases/download/v4.6.3/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq'"
  exit 1
fi


# Clone the test plan repo
rm -rf $script_dir/$TEMP_REPO
git clone $test_plan_repo $script_dir/$TEMP_REPO
rm -rf $script_dir/$POD_TEST_PLAN_DIR
mv $script_dir/$TEMP_REPO $script_dir/$POD_TEST_PLAN_DIR


# Assert test_plan_dir exsists  and that the jmx_file and properties_file are located at its surface level. 
if [ ! -d "$test_plan_dir" ]; then
  die "Directory '$test_plan_dir' does not exist! Use -h for help."
else
  if [ ! -f "$test_plan_dir/$JMX_FILE.jmx" ]; then
    die "'$JMX_FILE.jmx' does not exist at the surface level of directory '$test_plan_dir'.  Use './`basename ${BASH_SOURCE[0]}` -h' for help"
  elif [ ! -f "$test_plan_dir/$PROPERTIES_FILE.properties" ]; then
    die "'$PROPERTIES_FILE.properties' does not exist at the surface level of directory $test_plan_dir.  Use './`basename ${BASH_SOURCE[0]}` -h' for help"
  fi
fi


# Read in jmeter_ns which will be used in the new jmeter_namespace
jmeter_ns=`awk -F= '/kubermeter_namespace/{ print $2 }' $test_plan_dir/test.properties`
test_report_name=`awk -F= '/kubermeter_test_report_name/{ print $2 }' $test_plan_dir/test.properties`

if [ -z "$jmeter_ns" ] ; then
  echo "kubermeter_namespace is missing from $test_plan_dir/test.properties"
  exit 1
elif [ -z "$test_report_name" ] ; then
  echo "kubermeter_test_report_name is missing from $test_plan_dir/test.properties"
  exit 1
fi

jmeter_namespace="$JMETER_NAMESPACE_PREFIX$jmeter_ns"

echo "Current $JMETER_NAMESPACE_PREFIX* namespaces on the kubernetes cluster:"
echo
jm_namespaces=`kubectl get namespaces | grep -o "^$JMETER_NAMESPACE_PREFIX[a-z0-9\-]*"`
[ -z "$jm_namespaces" ] && jm_namespaces='<none>'
echo $jm_namespaces
echo

# Check if jmeter_namespace collides with existing namespaces
for jmns in $jm_namespaces; do # check if the new jmeter_namespace already exists.
  if [ $jmns == $jmeter_namespace ]; then
    echo "Namespace $jmeter_namespace already exists, please modify kubermeter_namespace in test.properties."
    exit 1
  fi
done

# Create the new name spaces and nodes
echo "Creating Namespace: $jmeter_namespace"
kubectl create namespace $jmeter_namespace
echo

echo "Creating Jmeter master pod.."
kubectl create -n $jmeter_namespace -f $script_dir/jmeter_master.yaml
echo

echo "Creating Jmeter slave pod(s)"
kubectl create -n $jmeter_namespace -f $script_dir/jmeter_slave_dep.yaml
echo

echo "Creating Jmeter slave service..."
kubectl create -n $jmeter_namespace -f $script_dir/jmeter_slave_svc.yaml
echo

echo "Waiting for all pods to be ready..."
echo
wait_time_elapsed="0"
wait_time_interval="5"
wait_time_min="20"
wait_time_max="180"
start_time=$(date +%s)
all_conatiners_ready=false
ip_pat='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
num_slaves=`yq e ".spec.replicas" ./jmeter_slave_dep.yaml`

while [[ "$all_conatiners_ready" = false ]]; do
  
  sleep $wait_time_interval

  now=$(date +%s)
  wait_time_elapsed=$(($now - $start_time))

  if [[ $wait_time_elapsed -ge $wait_time_max ]]; then
    echo "Containers are not ready within the limit of $wait_time_max seconds. Check the cluster health, \
and/or use 'kubectl delete ns $jmeter_namespace' to start over.\n"
    exit 1
  elif [[ $wait_time_elapsed -ge $wait_time_min ]]; then
    num_pod_ips=`kubectl -n $jmeter_namespace get pods -o wide | grep $JMETER_PODS_PREFIX | awk '{print $6}' | grep -Ec $ip_pat`
    [[ "$num_pod_ips" -eq $(($num_slaves + 1)) ]] && all_conatiners_ready=true || all_conatiners_ready=false
    kubectl -n $jmeter_namespace get pods -o wide
  fi

done

echo 
echo "JMeter master and slave pods are ready."
echo


# Get master pod details and push test files
master_pod=`kubectl -n $jmeter_namespace get po | grep jmeter-master | awk '{print $1}'`
msg "Pushing test files into jmeter-master pod $master_pod:$POD_KUBERMETER_DIR/$POD_TEST_PLAN_DIR..."
kubectl -n $jmeter_namespace cp $test_plan_dir $master_pod:$POD_KUBERMETER_DIR



# Get slave pods details and push test files
slave_pods=(`kubectl get po -n $jmeter_namespace | grep jmeter-slave | awk '{print $1}'`)
for slave_pod in ${slave_pods[@]}; do
  msg "Pushing test files into jmeter-slave pod $slave_pod:$POD_KUBERMETER_DIR/$POD_TEST_PLAN_DIR..."
  kubectl -n $jmeter_namespace cp $test_plan_dir $slave_pod:$POD_KUBERMETER_DIR
done


# Executing test and store test results remotely
msg "Starting the JMeter test..."
kubectl exec -ti -n $jmeter_namespace $master_pod -- /bin/bash /load_test $POD_KUBERMETER_DIR $POD_TEST_PLAN_DIR $JMX_FILE.jmx $PROPERTIES_FILE.properties $test_report_name.jtl

msg "Generating the JMeter HTML report..."
kubectl exec -ti -n $jmeter_namespace $master_pod -- /bin/bash /generate_report $POD_KUBERMETER_DIR/$test_report_name.jtl $POD_KUBERMETER_DIR/$test_report_name

msg "Pulling the test report and log from the master pod..."
kubectl -n $jmeter_namespace cp $master_pod:$POD_KUBERMETER_DIR/$test_report_name $test_report_name
kubectl -n $jmeter_namespace cp $master_pod:$POD_KUBERMETER_DIR/$test_report_name.jtl $test_report_name/$test_report_name.jtl

msg "Packing the test report and log file into ${test_report_name}.zip..."
zip -qr $test_report_name.zip $test_report_name

msg "Deleting namespace $jmeter_namespace..."
kubectl delete ns $jmeter_namespace

# Duplicated test_report_name fallback policy:

# msg "Checking if test results of $test_report_name already exists in the jmeter-master pod..."
# report_jtl_or_dir_count=`kubectl -n $jmeter_namespace exec -ti $master_pod -- find $POD_KUBERMETER_DIR/ -maxdepth 1 \
#   \( -type d -name ${test_report_name} -or -name ${test_report_name}.jtl \) | wc -l | xargs`

# if [ $((report_jtl_or_dir_count)) -lt 0 ]
# then
#   now=`date +"%H%M%S_%Y%b%d"`
#   new_test_report_name="${test_report_name}_${now}"
#   msg "${test_report_name} already esists in the jmeter master pod. Renaming it with current date as ${new_test_report_name}"
#   test_report_name=$new_test_report_name
# fi
