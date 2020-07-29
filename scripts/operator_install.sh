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

##### Dev Notes:
# We use `yml` instead of `yaml` for consistency (all service-settings and profiles require `yml`)

# On Linux, we assume we control the whole machine
# On OSX, we minimize impact to non-Spinnaker things

## TODO
# Move metrics server manifests (and see if we need it) - also detect existence
# Figure out nginx vs. traefik (nginx for m4m, traefik for ubuntu?, or use helm?)
# Exclude spinnaker namespace - not doing this
# Update 'public_ip'/'PUBLIC_IP' to 'public/endpoint/PUBLIC_ENDPOINT'
# Fix localhost public ip for m4m

# OOB application(s)
# Refactor all hydrates into a function: copy_and_hydrate

set -e

##### Functions
print_help () {
  set +x
  echo "Usage: install.sh"
  echo "               [-o|--oss]                                         : Install Open Source Spinnaker (instead of Armory Spinnaker)"
  echo "               [-P|--public-endpoint <PUBLIC_IP_OR_DNS_ADDRESS>]  : Specify public IP (or DNS name) for instance (rather than autodetection)"
  echo "               [-B|--base-dir <BASE_DIRECTORY>]                   : Specify root directory to use for manifests"
  set -x
}

install_k3s () {
  # curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy=traefik" K3S_KUBECONFIG_MODE=644 sh -
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $(cat ${BASE_DIR}/.hal/public_endpoint)" INSTALL_K3S_VERSION="v1.17.4+k3s1" K3S_KUBECONFIG_MODE=644 sh -
}

install_yq () {
  sudo curl -sfL https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64 -o /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
}

detect_endpoint () {
  if [[ ! -s ${BASE_DIR}/.hal/public_endpoint ]]; then
    if [[ -n "${PUBLIC_ENDPOINT}" ]]; then
      echo "Using provided public IP ${PUBLIC_ENDPOINT}"
      echo "${PUBLIC_ENDPOINT}" > ${BASE_DIR}/.hal/public_endpoint
      touch ${BASE_DIR}/.hal/public_endpoint_provided
    else
      if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
        while [[ ! -s ${BASE_DIR}/.hal/public_endpoint ]]; do
          echo "Detected cloud metadata endpoint"
          echo "Trying to determine public IP address (using 'dig +short TXT o-o.myaddr.l.google.com @ns1.google.com')"
          sleep 1
          dig +short TXT o-o.myaddr.l.google.com @ns1.google.com | sed 's|"||g' | tee ${BASE_DIR}/.hal/public_endpoint
        done
      else
        echo "No cloud metadata endpoint detected, detecting interface IP (and storing in ${BASE_DIR}/.hal/public_endpoint):"
        ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee ${BASE_DIR}/.hal/public_endpoint
        cat ${BASE_DIR}/.hal/public_endpoint
      fi
    fi
  else
    echo "Using existing Public IP from ${BASE_DIR}/.hal/public_endpoint"
    cat ${BASE_DIR}/.hal/public_endpoint
  fi
}

generate_passwords () {
  if [[ ! -s ${BASE_DIR}/.hal/.secret/minio_password ]]; then
    echo "Generating Minio password (${BASE_DIR}/.hal/.secret/minio_password):"
    openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/minio_password
  else
    echo "Minio password already exists (${BASE_DIR}/.hal/.secret/minio_password)"
  fi

  if [[ ! -s ${BASE_DIR}/.hal/.secret/mysql_password ]]; then
    echo "Generating MariaDB (MySQL) password (${BASE_DIR}/.hal/.secret/mysql_password):"
    openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/mysql_password
  else
    echo "MariaDB (MySQL) password already exists (${BASE_DIR}/.hal/.secret/mysql_password)"
  fi

  if [[ ! -s ${BASE_DIR}/.hal/.secret/spinnaker_password ]]; then
    echo "Generating Spinnaker password (${BASE_DIR}/.hal/.secret/spinnaker_password):"
    openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/spinnaker_password
  else
    echo "Spinnaker password already exists (${BASE_DIR}/.hal/.secret/spinnaker_password)"
  fi
}

copy_templates () {
  cp ${PROJECT_DIR}/templates/manifests/mariadb.yml ${BASE_DIR}/templates/mariadb.yml
  cp ${PROJECT_DIR}/templates/manifests/minio.yml ${BASE_DIR}/templates/minio.yml
}

copy_manifests () {
  ###
  # namespace.yml
  # spinnaker-ingress.yml

  cp ${PROJECT_DIR}/templates/manifests/namespace.yml ${BASE_DIR}/manifests/namespace.yml
  cp ${PROJECT_DIR}/templates/manifests/spinnaker-ingress.yml ${BASE_DIR}/manifests/spinnaker-ingress.yml

  cp -rv ${PROJECT_DIR}/operator ${BASE_DIR}/
}

hydrate_manifest_minio () {
  MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)

  # We actually don't need the sed entry for BASE_DIR anymore, but leaving for later
  if [[ ! -e ${BASE_DIR}/manifests/minio.yml ]]; then
    sed \
      -e "s|MINIO_PASSWORD|${MINIO_PASSWORD}|g" \
      -e "s|BASE_DIR|${BASE_DIR}|g" \
    ${BASE_DIR}/templates/minio.yml \
    | tee ${BASE_DIR}/manifests/minio.yml
  fi
}

hydrate_manifest_mariadb () {
  MYSQL_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/mysql_password)

  # We actually don't need the sed entry for BASE_DIR anymore, but leaving for later
  if [[ ! -e ${BASE_DIR}/manifests/mariadb.yml ]]; then
    sed \
      -e "s|MARIADB_PASSWORD|${MYSQL_PASSWORD}|g" \
      -e "s|BASE_DIR|${BASE_DIR}|g" \
    ${BASE_DIR}/templates/mariadb.yml \
    | tee ${BASE_DIR}/manifests/mariadb.yml
  fi
}

hydrate_manifests () {
  for f in ${BASE_DIR}/manifests/*; do
    sed -i \
      -e "s|NAMESPACE|${NAMESPACE}|g" \
      ${f}
  done
}

get_latest_version () {
  curl -sL https://halconfig.s3-us-west-2.amazonaws.com/versions.yml | grep 'version: ' | awk '{print $NF}' | sort | tail -1
}

######## Script starts here

OPEN_SOURCE=0
PUBLIC_ENDPOINT=""
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )
NAMESPACE=spinnaker

case "$(uname -s)" in
  Darwin*)
    LINUX=0
    BASE_DIR=~/minnaker
    ;;
  Linux*)
    LINUX=1
    BASE_DIR=/etc/spinnaker
    ;;
  *)
    LINUX=1
    BASE_DIR=/etc/spinnaker
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    -o|--oss)
      printf "Using OSS Spinnaker"
      OPEN_SOURCE=1
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

# Scaffold out directories
if [[ ${LINUX} -eq 1 ]]; then
  echo "Running minnaker setup for Linux"
  
  # OSS Halyard uses 1000; we're using 1000 for everything
  sudo mkdir -p ${BASE_DIR}/.kube
  sudo mkdir -p ${BASE_DIR}/.hal/.secret
  sudo mkdir -p ${BASE_DIR}/manifests
  sudo mkdir -p ${BASE_DIR}/templates
  sudo mkdir -p ${BASE_DIR}/operator

  sudo chown -R 1000 ${BASE_DIR}

  detect_endpoint

  install_k3s
  install_yq

  sudo env "PATH=$PATH" kubectl config set-context default --namespace spinnaker

else
  echo "Minnaker with Operator hasn't been built yet.  Sorry."
  exit 1
fi

# generate_spinnaker_password
generate_passwords
copy_templates
copy_manifests

hydrate_manifest_minio
hydrate_manifest_mariadb
hydrate_manifests

if [[ ${LINUX} -eq 1 ]]; then
  ### Create all manifests:
  # - namespace - must be created first
  # - halyard
  # - minio
  # - clusteradmin
  # - ingress
  kubectl apply -f ${BASE_DIR}/manifests/namespace.yml
  kubectl apply -f ${BASE_DIR}/manifests
    
  kubectl apply -f ${BASE_DIR}/operator/crds/
  kubectl apply -f ${BASE_DIR}/operator/deploy/namespace.yaml
  kubectl apply -f ${BASE_DIR}/operator/deploy/

  # This does this:
  # - update spinnaker password
  # - upate minio password
  # - update endpoints
  # - update version
  # TODO: Detect latest version
  # TODO: Use Kustomize variables

  SPINNAKER_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/spinnaker_password)
  MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)
  ENDPOINT=$(cat ${BASE_DIR}/.hal/public_endpoint)
  VERSION=$(get_latest_version)


  sed -i "s|ENDPOINT|${ENDPOINT}|g" \
    ${BASE_DIR}/operator/install/x-endpoint.yml
  sed -i "s|MINIO_PASSWORD|${MINIO_PASSWORD}|g" \
    ${BASE_DIR}/operator/install/x-minio-password.yml
  sed -i "s|SPINNAKER_PASSWORD|${SPINNAKER_PASSWORD}|g" \
    ${BASE_DIR}/operator/install/x-password.yml
  sed -i "s|VERSION|${VERSION}|g" \
    ${BASE_DIR}/operator/install/x-version.yml

  # yq versions of above
  # yq w -i ${BASE_DIR}/operator/install/x-endpoint.yml spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl https://${ENDPOINT}
  # yq w -i ${BASE_DIR}/operator/install/x-endpoint.yml spec.spinnakerConfig.config.security.apiSecurity.overrideBaseUrl https://${ENDPOINT}/api/v1
  # yq w -i ${BASE_DIR}/operator/install/x-endpoint.yml spec.spinnakerConfig.profiles.gate.security.user.password ${SPINNAKER_PASSWORD}
  # yq w -i ${BASE_DIR}/operator/install/x-minio-password.yml spec.spinnakerConfig.config.persistentStorage.s3.secretAccessKey ${MINIO_PASSWORD}
  # yq w -i ${BASE_DIR}/operator/install/x-version.yml spec.spinnakerConfig.config.version ${VERSION}

  kubectl apply -f ${BASE_DIR}/operator/install/manifests/service-account.yml
  kubectl apply -k ${BASE_DIR}/operator/install/

  set +x
  echo "It may take up to 10 minutes for this endpoint to work.  You can check by looking at running pods: 'kubectl get pods -A'"
  echo "https://$(cat ${BASE_DIR}/.hal/public_endpoint)"
  echo "username: 'admin'"
  echo "password: '$(cat ${BASE_DIR}/.hal/.secret/spinnaker_password)'"

  sleep 5
  kubectl get pods -A
fi
