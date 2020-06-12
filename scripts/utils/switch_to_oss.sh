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

set -e

# Linux only

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker
BASE_DIR=/etc/spinnaker

OLD_IMAGE=$(yq r ${BASE_DIR}/manifests/halyard.yml spec.template.spec.containers[0].image)
if [[ ${OLD_IMAGE} =~ "armory" ]]; then
  echo ${OLD_IMAGE} > ${BASE_DIR}/armory_image
else
  echo ${OLD_IMAGE} > ${BASE_DIR}/oss_image
fi

if [[ -f ${BASE_DIR}/oss_image ]]; then
  yq w -i ${BASE_DIR}/manifests/halyard.yml spec.template.spec.containers[0].image $(cat ${BASE_DIR}/oss_image)
else
  yq w -i ${BASE_DIR}/manifests/halyard.yml spec.template.spec.containers[0].image gcr.io/spinnaker-marketplace/halyard:stable
fi

kubectl apply -f ${BASE_DIR}/manifests/halyard.yml

sleep 5

while [[ $(kubectl --context ${KUBERNETES_CONTEXT} get statefulset -n ${NAMESPACE} halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
do
  echo "Waiting for Halyard pod to start"
  sleep 5;
done

yq r ${BASE_DIR}/.hal/config deploymentConfigurations[0].armory >> ${BASE_DIR}/halconfig_armory
yq d -i ${BASE_DIR}/.hal/config deploymentConfigurations[0].armory

VERSION=$(kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal version latest -q")
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal config version edit --version ${VERSION}"
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"