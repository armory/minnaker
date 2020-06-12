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

# Not (currently) designed for OSX

# This is used to 'reset' a Minnaker instance.  It regenerates the Minio and Gate passwords
# Also, it will do the following with the public endpoint:
# # If a new public endpoint is provided (with the flag -P), then the new endpoint will be used
# # Otherwise, if the previous public endpoint was provided was a flag, that endpoint will be used
# # Otherwise, the public endpoint will be re-detected

set -x
set -e

##### Functions
print_help () {
  set +x
  echo "Usage: regenerate_password.sh"
  set -x
}

generate_passwords () {
  # echo "Generating Minio password (${BASE_DIR}/.hal/.secret/minio_password):"
  # openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/minio_password

  echo "Generating Spinnaker password (${BASE_DIR}/.hal/.secret/spinnaker_password):"
  openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/spinnaker_password
}

# update_minio_password () {
#   MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)
#   yq w -i ${BASE_DIR}/manifests/minio.yml spec.template.spec.containers[0].env[1].value ${MINIO_PASSWORD}
#   yq w -i ${BASE_DIR}/.hal/config deploymentConfigurations[0].persistentStorage.s3.secretAccessKey ${MINIO_PASSWORD}
# }

update_spinnaker_password () {
  SPINNAKER_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/spinnaker_password)
  yq w -i ${BASE_DIR}/.hal/default/profiles/gate-local.yml security.user.password ${SPINNAKER_PASSWORD}
}

apply_changes () {
  while [[ $(kubectl get statefulset -n spinnaker halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
  do
    echo "Waiting for Halyard pod to start"
    sleep 2;
  done

  # We do this twice, because for some reason Kubernetes sometimes reports pods as healthy on first start after a reboot
  sleep 15

  while [[ $(kubectl get statefulset -n spinnaker halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
  do
    echo "Waiting for Halyard pod to start"
    sleep 2;
  done

  kubectl -n spinnaker exec -i halyard-0 -- hal deploy apply
}

# PUBLIC_ENDPOINT=""
BASE_DIR=/etc/spinnaker

while [ "$#" -gt 0 ]; do
  case "$1" in
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

PATH=${PATH}:/usr/local/bin
export PATH

generate_passwords

# update_minio_password
update_spinnaker_password

kubectl get apiservice

while [[ $(kubectl get apiservice | grep False | wc -l) -ne 0 ]];
do
  echo "Waiting for K3s to be up"
  sleep 5;
done

kubectl get apiservice

sleep 10

kubectl delete pods --all -A --force --grace-period=0

sleep 10

apply_changes

touch ${BASE_DIR}/.hal/password_generated

echo "https://$(cat /etc/spinnaker/.hal/public_endpoint)"
echo "username: 'admin'"
echo "password: '$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)'"
