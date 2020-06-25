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

set -x
set -e

# Takes two parameteters:
# - Filename for UUID
# - Purpose of UUID (only used for the output text)
function generate_or_use_uuid () {
  if [[ ! -s $1 ]]; then
    echo "Generating $2 UUID ($1)"
    uuidgen > ${1}
  else
    echo "$2 UUID already exists: $1: $(cat $1)"
  fi
}

BASE_DIR=/etc/spinnaker
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )

PVC="minio-pvc"
# We are using the bucket kayenta instead of the spinnaker bucket, because Kayenta crashes if it's using the same bucket (haven't dug into this yet)
FRONT50_BUCKET="spinnaker"
APPLICATION_NAME="democanary"

KAYENTA_BUCKET="kayenta"

cp -rv ${PROJECT_DIR}/templates/addons/demo ${BASE_DIR}/templates/

if [[ ! -s ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid ]]; then
  echo "Generating Canary Config UUID (${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)"
  uuidgen > ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid
else
  echo "Canary Config UUID already exists (${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)"
fi

if [[ ! -s ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid ]]; then
  echo "Generating Canary Config UUID (${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)"
  uuidgen > ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid
else
  echo "Canary Config UUID already exists (${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)"
fi

PIPELINE_UUID=$(cat ${BASE_DIR}/.hal/.secret/demo_canary_pipeline_uuid)
CANARY_CONFIG_UUID=$(cat ${BASE_DIR}/.hal/.secret/demo_canary_config_uuid)

MINIO_PATH=$(kubectl -n spinnaker get pv -ojsonpath="{.items[?(@.spec.claimRef.name==\"${PVC}\")].spec.hostPath.path}")

FRONT50_PATH=${MINIO_PATH}/${FRONT50_BUCKET}/front50
KAYENTA_PATH=${MINIO_PATH}/${KAYENTA_BUCKET}/kayenta
mkdir -p ${KAYENTA_PATH}/canary_config

mkdir -p ${FRONT50_PATH}/{applications,pipelines}
mkdir -p ${FRONT50_PATH}/applications/${APPLICATION_NAME}
mkdir -p ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}

TIMESTAMP=$(date +%s000)
ISO_TIMESTAMP=$(date +"%Y-%m-%dT%T.000Z")

# Create namespace(s)
set +e
kubectl create ns prod
set -e

# Create application
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/applications/${APPLICATION_NAME}/application-metadata.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-metadata.json

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/applications/${APPLICATION_NAME}/application-permissions.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-permissions.json

# Bump last-modified for application
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/applications/last-modified.json.tmpl \
  > ${FRONT50_PATH}/applications/last-modified.json

# Create the pipeline
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    -e "s|__PIPELINE_UUID__|${PIPELINE_UUID}|g" \
    -e "s|__CANARY_CONFIG_UUID__|${CANARY_CONFIG_UUID}|g" \
    ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/pipelines/PIPELINE_UUID/pipeline-metadata.json.tmpl \
    > ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}/pipeline-metadata.json

# Bump last-modified for pipeline
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/pipelines/last-modified.json.tmpl \
    > ${FRONT50_PATH}/pipelines/last-modified.json

# Create canary config
mkdir -p ${KAYENTA_PATH}/{canary_config,canary_archive,metric_pairs,metrics}
mkdir -p ${KAYENTA_PATH}/canary_config/${CANARY_CONFIG_UUID}

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    -e "s|__ISO_TIMESTAMP__|${ISO_TIMESTAMP}|g" \
    ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/canary_config/Latency.json.tmpl \
    > ${KAYENTA_PATH}/canary_config/${CANARY_CONFIG_UUID}/Latency.json

# Restart Kayenta to pick it up (not necessary, but makes the pickup faster)
kubectl -n spinnaker rollout restart deployment/spin-kayenta
