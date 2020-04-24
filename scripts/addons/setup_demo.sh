#!/bin/bash

set -x
set -e

# Takes two parameteters:
# - Filename for UUID
# - Purpose of UUID (only used for the output text)
function generate_or_use_uuid () {
  if [[ ! -f $1 ]]; then
    echo "Generating $2 UUID ($1)"
    uuidgen > ${1}
  else
    echo "$2 UUID already exists: $1: $(cat $1)"
  fi
}

BASE_DIR=/etc/spinnaker
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )

PVC="minio-pvc"
FRONT50_BUCKET="spinnaker"
APPLICATION_NAME="demok8s"

cp -rv ${PROJECT_DIR}/templates/addons/demo ${BASE_DIR}/templates/

UUID_PATH=${BASE_DIR}/.hal/.secret/demo_k8s_pipeline_uuid

generate_or_use_uuid ${UUID_PATH} "K8s Demo Pipeline"

PIPELINE_UUID=$(cat ${UUID_PATH})

MINIO_PATH=$(kubectl -n spinnaker get pv -ojsonpath="{.items[?(@.spec.claimRef.name==\"${PVC}\")].spec.hostPath.path}")

FRONT50_PATH=${MINIO_PATH}/${FRONT50_BUCKET}/front50

mkdir -p ${FRONT50_PATH}/{applications,pipelines}
mkdir -p ${FRONT50_PATH}/applications/${APPLICATION_NAME}
mkdir -p ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}

TIMESTAMP=$(date +%s000)
ISO_TIMESTAMP=$(date +"%Y-%m-%dT%T.000Z")

# Create namespace(s)
set +e
kubectl create ns dev
kubectl create ns test
kubectl create ns prod
set -e

# Create application
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/applications/${APPLICATION_NAME}/application-metadata.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-metadata.json

sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
  ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/applications/${APPLICATION_NAME}/application-permissions.json.tmpl \
  > ${FRONT50_PATH}/applications/${APPLICATION_NAME}/application-permissions.json

# Create the pipeline
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    -e "s|__PIPELINE_UUID__|${PIPELINE_UUID}|g" \
    ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/pipelines/PIPELINE_UUID/pipeline-metadata.json.tmpl \
    > ${FRONT50_PATH}/pipelines/${PIPELINE_UUID}/pipeline-metadata.json

# Bump last-modified for pipeline
sed -e "s|__TIMESTAMP__|${TIMESTAMP}|g" \
    ${BASE_DIR}/templates/demo/${APPLICATION_NAME}/pipelines/last-modified.json.tmpl \
    > ${FRONT50_PATH}/pipelines/last-modified.json