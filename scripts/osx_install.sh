#!/bin/bash
# set -x
set -e

# Install Minnaker in docker-desktop Kubernetes

##### Functions
print_help () {
  set +x
  echo "Usage: install.sh"
  echo "               [-o|--oss]                                         : Install Open Source Spinnaker (instead of Armory Spinnaker)"
  echo "               [-B|--base-dir <BASE_DIRECTORY>]                   : Specify root directory to use for manifests"
  set -x
}

######## Script starts here

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )

OPEN_SOURCE=0
PUBLIC_ENDPOINT=""
MAGIC_NUMBER=cafed00d
DEAD_MAGIC_NUMBER=cafedead
KUBERNETES_CONTEXT=docker-desktop
NAMESPACE=spinnaker

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Use install.sh to install on Linux"
  exit 1
fi

BASE_DIR=~/minnaker

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
  HALYARD_IMAGE="armory/halyard-armory:1.9.0"
fi

echo "Setting the Halyard Image to ${HALYARD_IMAGE}"

echo "Running minnaker setup for OSX"

# Scaffold out directories
# OSX / Docker Desktop has some fancy permissions so we do everything as ourselves
mkdir -p ${BASE_DIR}/templates/{manifests,profiles,service-settings}
mkdir -p ${BASE_DIR}/manifests
mkdir -p ${BASE_DIR}/.kube
mkdir -p ${BASE_DIR}/.hal/.secret
mkdir -p ${BASE_DIR}/.hal/default/{profiles,service-settings}

echo "localhost" > ${BASE_DIR}/.hal/public_endpoint

# detect_endpoint
# generate_passwords
copy_templates
# update_templates_for_linux
hydrate_templates_osx
conditional_copy

### Set up / check Kubernetes environment
curl -L https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml -o ${BASE_DIR}/manifests/nginx-ingress-controller.yaml

kubectl --context ${KUBERNETES_CONTEXT} get ns
if [[ $? -ne 0 ]]; then
  echo "Docker desktop not detected; bailing."
  exit 1
fi

### Create all manifests:
# - namespace - must be created first
# - NGINX ingress controller - must be created second
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

VERSION=$(kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal version latest -q")
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal config version edit --version ${VERSION}"
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"

echo "https://$(cat ${BASE_DIR}/.hal/public_endpoint)"

while [[ $(kubectl -n ${NAMESPACE} get pods --field-selector status.phase!=Running 2> /dev/null | wc -l) -ne 0 ]];
do
  echo "Waiting for all containers to be Running"
  kubectl -n ${NAMESPACE} get pods
  sleep 5
done

kubectl -n ${NAMESPACE} get pods
set +x
echo "It may take up to 10 minutes for this endpoint to work.  You can check by looking at running pods: 'kubectl -n ${NAMESPACE} get pods'"
echo "https://$(cat ${BASE_DIR}/.hal/public_endpoint)"
