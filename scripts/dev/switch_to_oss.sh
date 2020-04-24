#!/bin/bash
set -x
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

VERSION=$(kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal version latest -q")
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal config version edit --version ${VERSION}"
kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"