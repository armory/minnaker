#!/bin/bash
set -x
set -e

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker

BASE_DIR=/etc/spinnaker

for SVC in front50 igor rosco echo deck orca gate kayenta fiat clouddriver redis; do
  touch ${BASE_DIR}/.hal/default/service-settings/${SVC}.yml
  yq d -i ${BASE_DIR}/.hal/default/service-settings/${SVC}.yml kubernetes.serviceType
done

kubectl --context ${KUBERNETES_CONTEXT} --namespace ${NAMESPACE} delete svc -l app=spin

kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"