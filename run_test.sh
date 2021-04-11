#!/usr/bin/env bash
# https://betterdev.blog/minimal-safe-bash-script-template/

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF

Usage: 

$(basename "${BASH_SOURCE[0]}") [-h] test_plan_dir

test_plan_dir: The test plan directory, which must contain test.jmx and test.properties at surface level.

Create a new JMeter namespace and resources on an existing kuberntes cluster and then launch JMeter test.
It requires that you supply the test plan directory (`test_plan_dir`), which must contain `test.jmx` and `test.properties` at surface level.
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

JMETER_NAMESPACE_PREFIX=`awk -F= '/JMETER_NAMESPACE_PREFIX/{ print $2 }' ./kubermeter.properties`
POD_KUBERMETER_DIR='/tmp/kubermeter'
POD_TEST_PLAN_DIR='current_test_plan'
JMX_FILE='test'
PROPERTIES_FILE='test'
test_plan_dir="$1"
test_plan_dir_basename=`basename $test_plan_dir`


# Checking yq pacakge availability
if ! hash yq 2>/dev/null; then
  echo "Yaml processcor yq v4.6.3+ required: https://github.com/mikefarah/yq"
  echo "Run 'sudo wget https://github.com/mikefarah/yq/releases/download/v4.6.3/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq'"
  exit 1
fi


# Assert test_plan_dir exsists on the local machine and does not coincide with POD_TEST_PLAN_DIR, 
# and that the jmx_file and properties_file are located at its surface level. 
if [ ! -d "$test_plan_dir" ]; then
  die "Directory '$test_plan_dir' does not exist! Use -h for help."
elif [ $test_plan_dir_basename = $POD_TEST_PLAN_DIR ]; then
  die "Directory name '$test_plan_dir_basename' coincide with the reserved name '$POD_TEST_PLAN_DIR'. Please changed it to another one."
else
  if [ ! -f "$test_plan_dir/$JMX_FILE.jmx" ]; then
    die "'$JMX_FILE.jmx' does not exist at the surface level of directory '$test_plan_dir'.  Use './`basename ${BASH_SOURCE[0]}` -h' for help"
  elif [ ! -f "$test_plan_dir/$PROPERTIES_FILE.properties" ]; then
    die "'$PROPERTIES_FILE.properties' does not exist at the surface level of directory $test_plan_dir.  Use './`basename ${BASH_SOURCE[0]}` -h' for help"
  fi
fi


# Prompt for test_report_name: the generated JMeter test report and output log, which will also be used in the new jmeter_namespace
echo "Current $JMETER_NAMESPACE_PREFIX* namespaces on the kubernetes cluster:"
echo
jm_namespaces=`kubectl get namespaces | grep -o "^$JMETER_NAMESPACE_PREFIX\w*"`
[ -z "$jm_namespaces" ] && jm_namespaces='<none>'
echo $jm_namespaces
echo

while [[ -z "$test_report_name" ]]; do

  echo -n "Enter test_report_name to create a dedicated namespace for the test: $JMETER_NAMESPACE_PREFIX"
  read test_report_name

  if [ ! -z "$test_report_name" ] ; then # If test_report_name is not an empty string then
    jmeter_namespace="$JMETER_NAMESPACE_PREFIX$test_report_name"
    for jmns in $jm_namespaces; do # check if the new jmeter_namespace already exists.
      if [ $jmns == $jmeter_namespace ]; then
        echo "Namespace $jmeter_namespace already exists, please use a unique name."
        test_report_name='' # Reset test_report_name to empty upon name conflicts.
      fi
    done
  fi

done


# Prompt for number of slave nodes to be created
while [[ "$slave_num" -lt 1 || "$slave_num" -gt 20 ]]; do

  echo -n "How many JMeter slaves do you want to use? (1-20): "
  read slave_num

done


# Create the new name spaces and nodes
echo "Creating Namespace: $jmeter_namespace"
kubectl create namespace $jmeter_namespace
echo

echo "Creating Jmeter slave pod(s)"
yq e ".spec.replicas |= $slave_num" $script_dir/jmeter_slave_dep.yaml | kubectl create -n $jmeter_namespace -f -
echo

echo "Creating Jmeter slave service..."
kubectl create -n $jmeter_namespace -f $script_dir/jmeter_slave_svc.yaml
echo

echo "Creating Jmeter master pod.."
kubectl create -n $jmeter_namespace -f $script_dir/jmeter_master.yaml
echo

# Wait for all pods to be ready
waiting_msg="Waiting for all pods to be ready..."
iter="0"
max_iter="30"
check_interval_seconds="3"
all_conatiners_ready=false

while [[ "$all_conatiners_ready" = false && $iter -lt $max_iter ]]; do
  
  container_readiness_arr=(`kubectl get pods -n $jmeter_namespace \
    -o jsonpath='{.items[*].status.containerStatuses[*].ready}'`)
  [[ ${container_readiness_arr[*]} =~ true ]] && all_conatiners_ready=true || all_conatiners_ready=false
  waiting_msg="${waiting_msg}."
  echo -ne "$waiting_msg \r"
  sleep $check_interval_seconds
  let "iter++"

done

echo 

if [[ "$all_conatiners_ready" = false && $iter -eq $max_iter ]]; then
  echo "Containers are not ready before timing out. Check the cluster health, or \
use 'kubectl delete ns $jmeter_namespace' to start over.\n"
  exit 1
fi

echo "JMeter master and slave pods are ready."
echo


# Get master pod details and push test files
master_pod=`kubectl -n $jmeter_namespace get po | grep jmeter-master | awk '{print $1}'`
msg "Pushing test files into jmeter-master pod $master_pod:$POD_KUBERMETER_DIR/$test_plan_dir_basename ..."
kubectl -n $jmeter_namespace exec -ti $master_pod -- rm -rf $POD_KUBERMETER_DIR/$test_plan_dir_basename
kubectl -n $jmeter_namespace cp $test_plan_dir $master_pod:$POD_KUBERMETER_DIR/$test_plan_dir_basename
kubectl -n $jmeter_namespace exec -ti $master_pod -- cp -TR $POD_KUBERMETER_DIR/$test_plan_dir_basename $POD_KUBERMETER_DIR/$POD_TEST_PLAN_DIR 


# Get slave pods details and push test files
slave_pods=(`kubectl get po -n $jmeter_namespace | grep jmeter-slave | awk '{print $1}'`)
for slave_pod in ${slave_pods[@]}; do
  msg "Pushing test files into jmeter-slave pod $slave_pod:$POD_KUBERMETER_DIR/$test_plan_dir_basename"
  kubectl -n $jmeter_namespace exec -ti $slave_pod -- rm -rf $POD_KUBERMETER_DIR/$test_plan_dir_basename
  kubectl -n $jmeter_namespace cp $test_plan_dir $slave_pod:$POD_KUBERMETER_DIR/$test_plan_dir_basename
  kubectl -n $jmeter_namespace exec -ti $slave_pod -- cp -TR $POD_KUBERMETER_DIR/$test_plan_dir_basename $POD_KUBERMETER_DIR/$POD_TEST_PLAN_DIR 
done


# Executing test and store test results remotely
msg "Starting the JMeter test..."
kubectl exec -ti -n $jmeter_namespace $master_pod -- /bin/bash /load_test $POD_KUBERMETER_DIR $test_plan_dir $JMX_FILE.jmx $PROPERTIES_FILE.properties $test_report_name.jtl

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
