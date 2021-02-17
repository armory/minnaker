#!/bin/bash

################################################################################
# Copyright 2021 Armory, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# Install Minnaker in Ubuntu VM (will first install k3s)

#set -e

##### Functions
print_help () {
  set +x
  echo "Usage: install.sh"
  echo "               [-o|--oss]                                         : Install Open Source Spinnaker (instead of Armory Spinnaker)"
  echo "               [-P|--public-endpoint <PUBLIC_IP_OR_DNS_ADDRESS>]  : Specify public IP (or DNS name) for instance (rather than autodetection)"
  echo "               [-B|--base-dir <BASE_DIRECTORY>]                   : Specify root directory to use for manifests"
  echo "               [-G|--git-spinnaker]                               : Git Spinnaker Kustomize URL (instead of https://github.com/armory/spinnaker-kustomize-patches)"
  echo "               [--branch]                                         : Branch to clone (default 'minnaker')"
  echo "               [-n|--nowait]                                      : Don't wait for Spinnaker to come up"
  set -x
}

######## Script starts here

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )

OPEN_SOURCE=0
PUBLIC_ENDPOINT=""
PUBLIC_IP=""
MAGIC_NUMBER=cafed00d
DEAD_MAGIC_NUMBER=cafedead
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker
BASE_DIR=$PROJECT_DIR/spinsvc
SPIN_GIT_REPO="https://github.com/armory/spinnaker-kustomize-patches"
BRANCH=minnaker
SPIN_WATCH=1                 # Wait for Spinnaker to come up

OUT="$PROJECT_DIR/install.log"

function log() {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  ORANGE='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
  LEVEL=$1
  MSG=$2
  case $LEVEL in
  "INFO") HEADER_COLOR=$GREEN MSG_COLOR=$NS ;;
  "WARN") HEADER_COLOR=$ORANGE MSG_COLOR=$NS ;;
  "KUBE") HEADER_COLOR=$ORANGE MSG_COLOR=$CYAN ;;
  "ERROR") HEADER_COLOR=$RED MSG_COLOR=$NS ;;
  esac
  printf "${HEADER_COLOR}[%-5.5s]${NC} ${MSG_COLOR}%b${NC}" "${LEVEL}" "${MSG}"
  printf "[%-5.5s] %b" "${LEVEL}" "${MSG}" >>"$OUT"
}

function info() {
  log "INFO" "$1\n"
}

function warn() {
  log "WARN" "$1\n"
}

function error() {
  log "ERROR" "$1\n" && exit 1
}

function handle_generic_kubectl_error() {
  error "Error executing command:\n$ERR_OUTPUT"
}

function exec_kubectl_mutating() {
  log "KUBE" "$1\n"
  ERR_OUTPUT=$({ $1 >>"$OUT"; } 2>&1)
  EXIT_CODE=$?
  [[ $EXIT_CODE != 0 ]] && $2
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  error "Use osx_install.sh to install on OSX Docker Desktop"
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--oss)
      info "Using OSS Spinnaker"
      OPEN_SOURCE=1
      ;;
    -x)
      info "Excluding from Minnaker metrics"
      MAGIC_NUMBER=${DEAD_MAGIC_NUMBER}
      ;;
    -P|--public-endpoint)
      if [[ -n $2 ]]; then
        PUBLIC_IP=$2
        shift
      else
        error "--public-endpoint requires an IP address >&2"
        exit 1
      fi
      ;;
    -B|--base-dir)
      if [[ -n $2 ]]; then
        BASE_DIR=$2
        warn "Contents in $2 will be erased"
      else
        error "--base-dir requires a directory >&2"
        exit 1
      fi
      ;;
    -G|--git-spinnaker)
      if [[ -n $2 ]]; then
        SPIN_GIT_REPO=$2
        BRANCH=master
      else
        error "--git-spinnaker requires a git url >&2"
        exit 1
      fi
      ;;
    --branch)
      if [[ -n $2 ]]; then
        BRANCH=$2
      else
        info "Defaulting to branch 'minnaker' for $SPIN_GIT_REPO"
        BRANCH=minnaker
      fi
      ;;
    -n|--nowait)
      info "Will not wait for Spinnaker to come up"
      SPIN_WATCH=0
      ;;
    -h|--help)
      print_help
      exit 1
      ;;
  esac
  shift
done

# shellcheck disable=SC1090,SC1091
. "${PROJECT_DIR}/scripts/functions.sh"


if [[ ${OPEN_SOURCE} == 1 ]]; then
  info "Using OSS Spinnaker"
  SPIN_FLAVOR=oss
  VERSION=$(curl -s https://spinnaker.io/community/releases/versions/ | grep 'id="version-' | head -1 | sed -e 's/\(<[^<][^<]*>\)//g; /^$/d' | cut -d' ' -f2)
else
  info "Using Armory Spinnaker"
  SPIN_FLAVOR=armory
  VERSION=$(curl -sL https://halconfig.s3-us-west-2.amazonaws.com/versions.yml | grep 'version: ' | awk '{print $NF}' | sort | tail -1)
fi

info "Running minnaker setup for Linux"
info "Cloning repo: ${SPIN_GIT_REPO}#${BRANCH} into ${BASE_DIR}"

if [ -d "${BASE_DIR}" ]; then
  warn "${BASE_DIR} exists already.  FOLDER CONTENTS WILL GET OVERWRITTEN!"
  warn "PROCEEDING in 3 secs... (ctrl-C to cancel; use -B option to specify a different directory)"
  sleep 3
fi
rm -rf ${BASE_DIR}
git clone -b ${BRANCH} "${SPIN_GIT_REPO}" "${BASE_DIR}"
cd "${BASE_DIR}"

detect_endpoint
generate_passwords
update_endpoint
hydrate_templates

### Set up Kubernetes environment
info "--- Installing K3s ---"
install_k3s
info " --- END K3s --- "
info "Setting Kubernetes context to Spinnaker namespace"
sudo env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT} --namespace ${NAMESPACE}
info "Installing yq"
install_yq
info "Installing jq"
install_jq

### Deploy Spinnaker with Operator
cd "${BASE_DIR}"

SPIN_FLAVOR=${SPIN_FLAVOR} SPIN_WATCH=0 ./deploy.sh

# Install PACRD
exec_kubectl_mutating "kubectl apply -f https://engineering.armory.io/manifests/pacrd-1.0.1.yaml -n spinnaker" handle_generic_kubectl_error

echo '' >>~/.bashrc                                     # need to add empty line in case file doesn't end in newline
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# echo "It may take up to 10 minutes for this endpoint to work.  You can check by looking at running pods: 'kubectl -n ${NAMESPACE} get pods'"
info "https://${PUBLIC_ENDPOINT}"
info "username: 'admin'"
info "password: '${SPINNAKER_PASSWORD}'"

create_spin_endpoint

if [[ ${SPIN_WATCH} != 0 ]]; then
  watch kubectl get pods,spinsvc -n spinnaker
fi
