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
CURRENT_TEST_PLAN='current_test_plan'

rm -rf $script_dir/$TEMP_REPO
git clone $test_plan_repo $script_dir/$TEMP_REPO
rm -rf $script_dir/$CURRENT_TEST_PLAN
mv $script_dir/$TEMP_REPO $script_dir/$CURRENT_TEST_PLAN
