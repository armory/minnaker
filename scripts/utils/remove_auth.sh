#!/bin/bash
# set -x
set -e

# Linux only

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )
KUBERNETES_CONTEXT=default
NAMESPACE=spinnaker
BASE_DIR=/etc/spinnaker

mv ${BASE_DIR}/.hal/.secret/spinnaker_password ${BASE_DIR}/.hal/.secret/spinnaker_password_removed
yq d -i ${BASE_DIR}/.hal/default/profiles/gate-local.yml security
sed -i 's|^window.spinnakerSettings.authEnabled|# window.spinnakerSettings.authEnabled|g' ${BASE_DIR}/.hal/default/profiles/settings-local.js

kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"