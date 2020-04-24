#!/bin/bash
set -x
set -e

# The filename is intentionally prometheus_install and not install_prometheus so install.sh continues to autocomplete

BASE_DIR=/etc/spinnaker
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

tee /etc/spinnaker/prometheus/custom/patch.yml <<-'EOF'
spec:
  routePrefix: /prometheus
  externalUrl: https://PUBLIC_ENDPOINT/prometheus
EOF

sed -i "s|PUBLIC_ENDPOINT|$(cat /etc/spinnaker/.hal/public_endpoint)|g" /etc/spinnaker/prometheus/custom/patch.yml
yq m -i ${BASE_DIR}/prometheus/custom/prometheus.yaml /etc/spinnaker/prometheus/custom/patch.yml

yq d -i ${BASE_DIR}/prometheus/custom/prometheus.yaml spec.serviceMonitorSelector

tee -a ${BASE_DIR}/prometheus/custom/prometheus.yaml <<-'EOF'
  serviceMonitorSelector: {}
  serviceMonitorNamespaceSelector: {}
EOF

kubectl apply -n default -f ${BASE_DIR}/prometheus/custom/prometheus.yaml

# Set up ingress with auth (same username/password as Spinnaker)
# Set up service for Kayenta to get to Prometheus

# sudo apt-get update
# sudo apt-get install apache2-utils -y
# htpasswd -b -c auth admin $(cat /etc/spinnaker/.hal/.secret/spinnaker_password)
# kubectl -n default create secret generic prometheus-auth --from-file auth

kubectl -n default apply -f ${BASE_DIR}/templates/prometheus/prometheus-service.yaml
kubectl -n default apply -f ${BASE_DIR}/templates/prometheus/prometheus-ingress-local.yaml