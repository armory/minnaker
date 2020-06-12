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

# The filename is intentionally prometheus_install and not install_prometheus so install.sh continues to autocomplete

BASE_DIR=~/minnaker
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )

curl -L https://github.com/coreos/prometheus-operator/archive/v0.37.0.tar.gz -o /tmp/prometheus-operator.tgz
tar -xzvf /tmp/prometheus-operator.tgz -C ${BASE_DIR}/

mv ${BASE_DIR}/prometheus-operator-* ${BASE_DIR}/prometheus

cp -rv ${PROJECT_DIR}/templates/addons/prometheus ${BASE_DIR}/templates

# Installs operator into default namespace.  Has these resources:
# - clusterrolebinding.rbac.authorization.k8s.io/prometheus-operator
# - clusterrole.rbac.authorization.k8s.io/prometheus-operator
# - deployment.apps/prometheus-operator
# - serviceaccount/prometheus-operator
# - servicemonitor.monitoring.coreos.com/prometheus-operator
# - service/prometheus-operator

# Have to create the CRD first
kubectl apply -n default -f ${BASE_DIR}/prometheus/example/prometheus-operator-crd
sleep 2
kubectl apply -n default -f ${BASE_DIR}/prometheus/example/rbac/prometheus-operator

# Installs a Prometheus (CRD) instance in the default namespace:
# - clusterrolebinding.rbac.authorization.k8s.io/prometheus
# - clusterrole.rbac.authorization.k8s.io/prometheus
# - serviceaccount/prometheus
# - prometheus.monitoring.coreos.com/prometheus

kubectl apply -n default -f ${BASE_DIR}/prometheus/example/rbac/prometheus

mkdir -p ${BASE_DIR}/prometheus/custom

# Create a custom CR, with these changes:
# - Patch with routePrefix and externalUrl
# - Remove serviceMonitorSelector
# - Add empty serviceMonitorSelector and serviceMonitorNamespaceSelector (yq doesn't support setting to empty)

cp ${BASE_DIR}/prometheus/example/rbac/prometheus/prometheus.yaml ${BASE_DIR}/prometheus/custom/

tee ${BASE_DIR}/prometheus/custom/patch.yml <<-'EOF'
spec:
  routePrefix: /prometheus
  externalUrl: https://PUBLIC_ENDPOINT/prometheus
EOF

sed -i.bak "s|PUBLIC_ENDPOINT|$(cat ${BASE_DIR}/.hal/public_endpoint)|g" ${BASE_DIR}/prometheus/custom/patch.yml
yq m -i ${BASE_DIR}/prometheus/custom/prometheus.yaml ${BASE_DIR}/prometheus/custom/patch.yml

yq d -i ${BASE_DIR}/prometheus/custom/prometheus.yaml spec.serviceMonitorSelector

tee -a ${BASE_DIR}/prometheus/custom/prometheus.yaml <<-'EOF'
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
EOF

kubectl apply -n default -f ${BASE_DIR}/prometheus/custom/prometheus.yaml

# Set up ingress with auth (same username/password as Spinnaker)
# Set up service for Kayenta to get to Prometheus

kubectl -n default apply -f ${BASE_DIR}/templates/prometheus/prometheus-service.yaml
kubectl -n default apply -f ${BASE_DIR}/templates/prometheus/prometheus-ingress-noauth.yaml