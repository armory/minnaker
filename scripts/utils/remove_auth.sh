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

mv ${BASE_DIR}/.hal/.secret/spinnaker_password ${BASE_DIR}/.hal/.secret/spinnaker_password_removed
yq d -i ${BASE_DIR}/.hal/default/profiles/gate-local.yml security
sed -i 's|^window.spinnakerSettings.authEnabled|# window.spinnakerSettings.authEnabled|g' ${BASE_DIR}/.hal/default/profiles/settings-local.js

kubectl --context ${KUBERNETES_CONTEXT} -n ${NAMESPACE} exec -i halyard-0 -- sh -c "hal deploy apply"