#!/bin/bash
set -x
set -e

# The filename is intentionally prometheus_install and not install_prometheus so install.sh continues to autocomplete

BASE_DIR=/etc/spinnaker

curl -L https://github.com/coreos/prometheus-operator/archive/v0.37.0.tar.gz -o /tmp/prometheus-operator.tgz
tar -xzvf /tmp/prometheus-operator.tgz -C ${BASE_DIR}/

mv ${BASE_DIR}/prometheus-operator-* ${BASE_DIR}/prometheus

# Installs operator into default namespace.  Has these resources:
# - clusterrolebinding.rbac.authorization.k8s.io/prometheus-operator
# - clusterrole.rbac.authorization.k8s.io/prometheus-operator
# - deployment.apps/prometheus-operator
# - serviceaccount/prometheus-operator
# - servicemonitor.monitoring.coreos.com/prometheus-operator
# - service/prometheus-operator
kubectl apply -n default -f ${BASE_DIR}/prometheus/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
sleep 2
kubectl apply -n default -f ${BASE_DIR}/prometheus/example/rbac/prometheus-operator

###### HAVE TO REDO THE ABOVE

# Installs a Prometheus (CRD) instance in the default namespace:
# - clusterrolebinding.rbac.authorization.k8s.io/prometheus
# - clusterrole.rbac.authorization.k8s.io/prometheus
# - serviceaccount/prometheus
# - prometheus.monitoring.coreos.com/prometheus

# Have to create the CRD first
kubectl apply -n default -f ${BASE_DIR}/prometheus/example/rbac/prometheus

# Ingress
mkdir -p ${BASE_DIR}/prometheus/custom

tee ${BASE_DIR}/prometheus/custom/ingress.yaml <<-'EOF'
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: prom-ingress
spec:
  rules:
  - http:
      paths:
      - backend:
          serviceName: prometheus-operated
          servicePort: 9090
        path: /prometheus
EOF

kubectl apply -n default -f ${BASE_DIR}/prometheus/custom/ingress.yaml

cp ${BASE_DIR}/prometheus/example/rbac/prometheus/prometheus.yaml ${BASE_DIR}/prometheus/custom/

# tee /etc/spinnaker/prometheus/custom/patch.yml <<-'EOF'
# spec:
#   routePrefix: /prometheus
#   externalUrl: https://PUBLIC_ENDPOINT/prometheus
#   serviceMonitorSelector:
#     matchLabels:
#       prometheus: monitored
# EOF

tee /etc/spinnaker/prometheus/custom/patch.yml <<-'EOF'
spec:
  routePrefix: /prometheus
  externalUrl: https://PUBLIC_ENDPOINT/prometheus
EOF

sed -i "s|PUBLIC_ENDPOINT|$(cat /etc/spinnaker/.hal/public_endpoint)|g" /etc/spinnaker/prometheus/custom/patch.yml

yq d -i ${BASE_DIR}/prometheus/custom/prometheus.yaml spec.serviceMonitorSelector

yq m -i ${BASE_DIR}/prometheus/custom/prometheus.yaml /etc/spinnaker/prometheus/custom/patch.yml

tee -a ${BASE_DIR}/prometheus/custom/prometheus.yaml <<-'EOF'
  serviceMonitorNamespaceSelector: {}
  serviceMonitorSelector: {}
EOF

kubectl apply -n default -f ${BASE_DIR}/prometheus/custom/prometheus.yaml

######### DELETE the default matchlabels

# kubectl patch -n default prometheus --patch $(cat /etc/spinnaker/prometheus/custom/patch.yml)

sudo apt-get update
sudo apt-get install apache2-utils -y
htpasswd -b -c auth admin $(cat /etc/spinnaker/.hal/.secret/spinnaker_password)
kubectl -n default create secret generic prometheus-auth --from-file auth

tee ${BASE_DIR}/prometheus/custom/ingress-auth.yaml <<-'EOF'
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: prom-ingress
  annotations:
    traefik.ingress.kubernetes.io/auth-type: basic
    traefik.ingress.kubernetes.io/auth-secret: prometheus-auth
spec:
  rules:
  - http:
      paths:
      - backend:
          serviceName: prometheus-operated
          servicePort: 9090
        path: /prometheus
EOF

kubectl -n default apply -f ${BASE_DIR}/prometheus/custom/ingress-auth.yaml

###############################

tee ${BASE_DIR}/prometheus/custom/prometheus-service.yml <<-'EOF'
apiVersion: v1
kind: Service
metadata:
  name: prometheus
spec:
  ports:
  - name: web
    port: 9090
    protocol: TCP
    targetPort: web
  selector:
    app: prometheus
  type: ClusterIP
EOF

kubectl -n default apply -f ${BASE_DIR}/prometheus/custom/prometheus-service.yml

