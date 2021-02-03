#!/bin/bash

################################################################################
# Copyright 2020 Armory, Inc.
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

set -e

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
MAGIC_NUMBER=cafed00d
DEAD_MAGIC_NUMBER=cafedead
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker
BASE_DIR=/home/ubuntu/spinnaker
SPIN_GIT_REPO="https://github.com/armory/spinnaker-kustomize-patches"
BRANCH=minnaker
SPIN_WATCH=1                 # Wait for Spinnaker to come up

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "Use osx_install.sh to install on OSX Docker Desktop"
  exit 1
fi


while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--oss)
      echo "Using OSS Spinnaker"
      OPEN_SOURCE=1
      ;;
    -x)
      echo "Excluding from Minnaker metrics"
      MAGIC_NUMBER=${DEAD_MAGIC_NUMBER}
      ;;
    -P|--public-endpoint)
      if [[ -n $2 ]]; then
        PUBLIC_ENDPOINT=$2
        shift
      else
<<<<<<< HEAD
<<<<<<< HEAD
        echo "ERROR: --public-endpoint requires an IP address >&2"
=======
        echo "Error: --public-endpoint requires an IP address >&2"
>>>>>>> feat(operator-v2): Use spinnaker-kustomize-patches for operator installs
=======
        echo "ERROR: --public-endpoint requires an IP address >&2"
>>>>>>> Add installation of jq
        exit 1
      fi
      ;;
    -B|--base-dir)
      if [[ -n $2 ]]; then
        BASE_DIR=$2
      else
<<<<<<< HEAD
<<<<<<< HEAD
        echo "ERROR: --base-dir requires a directory >&2"
        exit 1
      fi
      ;;
    -G|--git-spinnaker)
      if [[ -n $2 ]]; then
        SPIN_GIT_REPO=$2
        BRANCH=master
      else
        echo "ERROR: --git-spinnaker requires a git url >&2"
        exit 1
      fi
      ;;
    --branch)
      if [[ -n $2 ]]; then
        BRANCH=$2
      else
        echo "INFO: Defaulting to branch 'minnaker' for $SPIN_GIT_REPO"
        BRANCH=minnaker
      fi
      ;;
=======
        echo "Error: --base-dir requires a directory >&2"
=======
        echo "ERROR: --base-dir requires a directory >&2"
>>>>>>> Add installation of jq
        exit 1
      fi
      ;;
    -G|--git-spinnaker)
      if [[ -n $2 ]]; then
        SPIN_GIT_REPO=$2
      else
        echo "ERROR: --git-spinnaker requires a directory >&2"
        exit 1
      fi
      ;;
>>>>>>> feat(operator-v2): Use spinnaker-kustomize-patches for operator installs
    -n|--nowait)
      echo "Will not wait for Spinnaker to come up"
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

# install prereqs jq
# if jq is not installed
if ! jq --help > /dev/null 2>&1; then
  # only try installing if a Debian system
  if apt-get -v > /dev/null 2>&1; then 
    echo "Using apt-get to install jq"
    sudo apt-get install -y jq
  else
    echo "ERROR: Unsupported OS! Cannot automatically install jq. Please try install jq first before rerunning this script"
    exit 2
  fi
fi

if [[ ${OPEN_SOURCE} -eq 1 ]]; then
  echo "Using OSS Spinnaker"
  SPIN_FLAVOR=oss
  VERSION=$(curl -s https://spinnaker.io/community/releases/versions/ | grep 'id="version-' | head -1 | sed -e 's/\(<[^<][^<]*>\)//g; /^$/d' | cut -d' ' -f2)
else
  echo "Using Armory Spinnaker"
  SPIN_FLAVOR=armory
  VERSION=$(curl -sL https://halconfig.s3-us-west-2.amazonaws.com/versions.yml | grep 'version: ' | awk '{print $NF}' | sort | tail -1)
fi

echo "Running minnaker setup for Linux"
echo "Will use the following spinnaker-kustomize-patch repo: ${SPIN_GIT_REPO}"

# Scaffold out directories
# OSS Halyard uses 1000; we're using 1000 for everything
sudo mkdir -p "${BASE_DIR}/.kube"
sudo mkdir -p "${BASE_DIR}/.hal/.secret"
sudo chown -R 1000 "${BASE_DIR}"

detect_endpoint
generate_passwords

### Fix up operator manifests
SPINNAKER_PASSWORD=$(cat "${BASE_DIR}/.hal/.secret/spinnaker_password")
# uncomment when functions.sh generates minio password
#MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)
PUBLIC_ENDPOINT="${PUBLIC_ENDPOINT:-spinnaker.$(cat "${BASE_DIR}/.hal/public_endpoint").nip.io}"   # use nip.io which is a DNS that will always resolve.

# Clone armory/spinnaker-kustomize-patches branch:minnaker and pre-fill manifests
rm -rf ${BASE_DIR}/spinsvc
git clone -b ${BRANCH} "${SPIN_GIT_REPO}" "${BASE_DIR}/spinsvc"
cd "${BASE_DIR}/spinsvc"

rm kustomization.yml
ln -s recipes/kustomization-minnaker.yml kustomization.yml

sed -i "s|spinnaker.mycompany.com|${PUBLIC_ENDPOINT}|g" expose/ingress-traefik.yml
sed -i "s|spinnaker.mycompany.com|${PUBLIC_ENDPOINT}|g" expose/patch-urls.yml
sed -i "s|^http-password=xxx|http-password=${SPINNAKER_PASSWORD}|g" secrets/secrets-example.env
# uncomment when functions.sh generates minio password
#sed -i "s|^minioAccessKey=changeme|minioAccessKey=${MINIO_PASSWORD}|g" secrets/secrets-example.env
sed -i "s|username2replace|admin|g" security/patch-basic-auth.yml
sed -i -r "s|(^.*)version: .*|\1version: ${VERSION}|" core_config/patch-version.yml
sed -i "s|token|# token|g" accounts/git/patch-github.yml
sed -i "s|username|# username|g" accounts/git/patch-gitrepo.yml
sed -i "s|token|# token|g" accounts/git/patch-gitrepo.yml

if [[ ${OPEN_SOURCE} -eq 0 ]]; then
  sed -i "s|xxxxxxxx-.*|${MAGIC_NUMBER}$(uuidgen | cut -c 9-)|" armory/patch-diagnostics.yml
else
  # remove armory related patches
  sed -i "s|- armory|#- armory|g" recipes/kustomization-minnaker.yml
fi

### Set up Kubernetes environment
echo "Installing K3s"
install_k3s
echo "Setting kubernetes context to Spinnaker namespace"
sudo env "PATH=$PATH" kubectl config set-context ${KUBERNETES_CONTEXT} --namespace ${NAMESPACE}
echo "Installing yq"
install_yq

### Deploy Spinnaker with Operator
cd "${BASE_DIR}/spinsvc"

set -x
SPIN_FLAVOR=${SPIN_FLAVOR} SPIN_WATCH=${SPIN_WATCH} ./deploy.sh
set +x

#ln -s "${BASE_DIR}" "${HOME}/spinnaker"
#ln -s "${BASE_DIR}/operator" "${HOME}/install"

echo '' >>~/.bashrc                                     # need to add empty line in case file doesn't end in newline
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

echo "It may take up to 10 minutes for this endpoint to work.  You can check by looking at running pods: 'kubectl -n ${NAMESPACE} get pods'"
echo "http://${PUBLIC_ENDPOINT}"
echo "username: 'admin'"
echo "password: '${SPINNAKER_PASSWORD}'"

