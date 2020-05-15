#!/bin/bash
# set -x
set -e

# Install Minnaker in Ubuntu VM (will first install k3s)

##### Functions
print_help () {
  set +x
  echo "Usage: install.sh"
  echo "               [-o|--oss]                                         : Install Open Source Spinnaker (instead of Armory Spinnaker)"
  echo "               [-P|--public-endpoint <PUBLIC_IP_OR_DNS_ADDRESS>]  : Specify public IP (or DNS name) for instance (rather than detecting using ifconfig.co)"
  echo "               [-B|--base-dir <BASE_DIRECTORY>]                   : Specify root directory to use for manifests"
  set -x
}

######## Script starts here

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )

OPEN_SOURCE=0
PUBLIC_ENDPOINT=""
MAGIC_NUMBER=cafed00d
DEAD_MAGIC_NUMBER=cafedead
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Use osx_install.sh to install on OSX Docker Desktop"
  exit 1
fi

BASE_DIR=/etc/spinnaker

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--oss)
      printf "Using OSS Spinnaker"
      OPEN_SOURCE=1
      ;;
    -x)
      printf "Excluding from Minnaker metrics"
      MAGIC_NUMBER=${DEAD_MAGIC_NUMBER}
      ;;
    -P|--public-endpoint)
      if [ -n $2 ]; then
        PUBLIC_ENDPOINT=$2
        shift
      else
        printf "Error: --public-endpoint requires an IP address >&2"
        exit 1
      fi
      ;;
    -B|--base-dir)
      if [ -n $2 ]; then
        BASE_DIR=$2
      else
        printf "Error: --base-dir requires a directory >&2"
        exit 1
      fi
      ;;
    -h|--help)
      print_help
      exit 1
      ;;
  esac
  shift
done

. ${PROJECT_DIR}/scripts/functions.sh

if [[ ${OPEN_SOURCE} -eq 1 ]]; then
  printf "Using OSS Spinnaker"
  HALYARD_IMAGE="gcr.io/spinnaker-marketplace/halyard:stable"
else
  printf "Using Armory Spinnaker"
  # This is defined in functions.sh
  HALYARD_IMAGE="${ARMORY_HALYARD_IMAGE}"
fi

echo "Setting the Halyard Image to ${HALYARD_IMAGE}"

echo "Running minnaker setup for Linux"
  
# Scaffold out directories
# OSS Halyard uses 1000; we're using 1000 for everything
sudo mkdir -p ${BASE_DIR}/templates/{manifests,profiles,service-settings}
sudo mkdir -p ${BASE_DIR}/manifests
sudo mkdir -p ${BASE_DIR}/.kube
sudo mkdir -p ${BASE_DIR}/.hal/.secret
sudo mkdir -p ${BASE_DIR}/.hal/default/{profiles,service-settings}

sudo chown -R 1000 ${BASE_DIR}

detect_endpoint
generate_passwords
copy_templates
update_templates_for_auth
hydrate_templates
conditional_copy

### Set up Kubernetes environment
install_k3s
sudo env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT} --namespace ${NAMESPACE}
install_yq

### Create all manifests:
# - namespace - must be created first
# - halyard
# - minio
# - clusteradmin
# - ingress
kubectl --context ${KUBERNETES_CONTEXT} apply -f ${BASE_DIR}/manifests/namespace.yml
kubectl --context ${KUBERNETES_CONTEXT} apply -f ${BASE_DIR}/manifests
  
######## Bootstrap
while [[ $(kubectl --context ${KUBERNETES_CONTEXT} get statefulset -n ${NAMESPACE} halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
do
  echo "Waiting for Halyard pod to start"
  sleep 5;
done

sleep 5;
create_hal_shortcut
create_spin_endpoint

VERSION=$(kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal version latest -q")
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal config version edit --version ${VERSION}"
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"

spin_endpoint

while [[ $(kubectl -n ${NAMESPACE} get pods --field-selector status.phase!=Running 2> /dev/null | wc -l) -ne 0 ]];
do
  echo "Waiting for all containers to be Running"
  kubectl -n ${NAMESPACE} get pods
  sleep 5
done

kubectl -n ${NAMESPACE} get pods

echo 'source <(kubectl completion bash)' >>~/.bashrc

set +x
echo "It may take up to 10 minutes for this endpoint to work.  You can check by looking at running pods: 'kubectl -n ${NAMESPACE} get pods'"
spin_endpoint
