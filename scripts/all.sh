#!/bin/bash
set -x
set -e

# TODO paramaterize
VERSION=2.15.0
SPINUSER=$(id -u 100 -n)

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy=traefik" sh -

# Scaffold out directories
sudo mkdir -p /etc/spinnaker/{.hal/.secret,.hal/default/profiles,.kube,manifests,tools}
sudo chown -R ${SPINUSER} /etc/spinnaker

# Install Metrics server
sudo -u ${SPINUSER} git clone https://github.com/kubernetes-incubator/metrics-server.git /etc/spinnaker/manifests/metrics-server
sudo kubectl apply -f /etc/spinnaker/manifests/metrics-server/deploy/1.8+/

# Install Docker (TODO: Decide whether we need to use yum or apt or something else)
sudo snap install docker

PUBLIC_IP=$(curl ifconfig.co)
PRIVATE_IP=$(ip r get 8.8.8.8 | awk 'NR==1{print $NF}')
MINIO_PASSWORD=$(openssl rand -base64 32)
SPINNAKER_PASSWORD=$(openssl rand -base64 32)

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/version <<-EOF
${VERSION}
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/public_ip <<-EOF
${PUBLIC_IP}
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/private_ip <<-EOF
${PRIVATE_IP}
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/minio_password <<-EOF
${MINIO_PASSWORD}
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/spinnaker_password <<-EOF
${SPINNAKER_PASSWORD}
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/manifests/minio.yaml <<-'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: minio
    spec:
      volumes:
      - name: storage
        hostPath:
          path: /etc/spinnaker/minio
          type: DirectoryOrCreate
      containers:
      - name: minio
        image: minio/minio
        args:
        - server
        - /storage
        env:
        # MinIO access key and secret key
        - name: MINIO_ACCESS_KEY
          value: "minio"
        - name: MINIO_SECRET_KEY
          value: "PASSWORD"
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: storage # must match the volume name, above
          mountPath: "/storage"
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  ports:
    - port: 9000
      targetPort: 9000
      protocol: TCP
  selector:
    app: minio
EOF

sudo -u ${SPINUSER} sed -i "s|PASSWORD|${MINIO_PASSWORD}|g" /etc/spinnaker/manifests/minio.yaml

sudo -u ${SPINUSER} tee /etc/spinnaker/manifests/expose-spinnaker.yaml <<-'EOF'
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: spin
    cluster: spin-deck-lb
  name: spin-deck-lb
  namespace: spinnaker
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 9000
  selector:
    app: spin
    cluster: spin-deck
  sessionAffinity: None
  type: LoadBalancer
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: spin
    cluster: spin-gate-lb
  name: spin-gate-lb
  namespace: spinnaker
spec:
  ports:
  - port: 8084
    protocol: TCP
    targetPort: 8084
  selector:
    app: spin
    cluster: spin-gate
  type: LoadBalancer
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/default/profiles/front50-local.yml <<-'EOF'
spinnaker.s3.versioning: false
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/default/profiles/settings-local.js <<-EOF
window.spinnakerSettings.authEnabled = true;
EOF

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/default/profiles/gate-local.yml <<-EOF
security:
  basicform:
    enabled: true
  user:
    name: admin
    password: SPINNAKER_PASSWORD
EOF

sudo -u ${SPINUSER} sed -i "s|SPINNAKER_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)|g" \
    /etc/spinnaker/.hal/default/profiles/gate-local.yml

sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/config-seed <<-'EOF'
currentDeployment: default
deploymentConfigurations:
- name: default
  version: 2.15.0
  providers:
    kubernetes:
      enabled: true
      accounts:
      - name: spinnaker
        providerVersion: V2
        kubeconfigFile: /home/spinnaker/.hal/.secret/kubeconfig-spinnaker-sa
        onlySpinnakerManaged: true
      primaryAccount: spinnaker
  deploymentEnvironment:
    size: SMALL
    type: Distributed
    accountName: spinnaker
    location: spinnaker
  persistentStorage:
    persistentStoreType: s3
    s3:
      bucket: spinnaker
      rootFolder: front50
      pathStyleAccess: true
      endpoint: http://minio.minio:9000
      accessKeyId: minio
      secretAccessKey: MINIO_PASSWORD
  features:
    artifacts: true
  security:
    apiSecurity:
      ssl:
        enabled: false
      overrideBaseUrl: http://PUBLIC_IP:8084
    uiSecurity:
      ssl:
        enabled: false
      overrideBaseUrl: http://PUBLIC_IP
  artifacts:
    http:
      enabled: true
      accounts: []
EOF

sudo -u ${SPINUSER} sed -i "s|MINIO_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/minio_password)|g" /etc/spinnaker/.hal/config-seed
sudo -u ${SPINUSER} sed -i "s|PUBLIC_IP|$(cat /etc/spinnaker/.hal/.secret/public_ip)|g" /etc/spinnaker/.hal/config-seed

# Only seed config if it doesn't already exist
if [[ ! -e /etc/spinnaker/.hal/config ]]; then
  sudo -u ${SPINUSER} cp /etc/spinnaker/.hal/config-seed /etc/spinnaker/.hal/config
fi

# Set up Kubernetes credentials

sudo -u ${SPINUSER} curl -L https://github.com/armory/spinnaker-tools/releases/download/0.0.6/spinnaker-tools-linux -o /etc/spinnaker/tools/spinnaker-tools

sudo -u ${SPINUSER} chmod +x /etc/spinnaker/tools/spinnaker-tools

sudo /etc/spinnaker/tools/spinnaker-tools create-service-account \
    -c default \
    -i /etc/rancher/k3s/k3s.yaml \
    -o /etc/spinnaker/.kube/localhost-config \
    -n spinnaker \
    -s spinnaker-sa

sudo chown ${SPINUSER} /etc/spinnaker/.kube/localhost-config

sudo -u ${SPINUSER} sed "s/localhost/${PRIVATE_IP}/g" /etc/spinnaker/.kube/localhost-config \
    | sudo -u ${SPINUSER} tee /etc/spinnaker/.kube/config

sudo -u ${SPINUSER} cp -rpv /etc/spinnaker/.kube/config \
    /etc/spinnaker/.hal/.secret/kubeconfig-spinnaker-sa

# Install Minio and service

sudo kubectl apply -f /etc/spinnaker/manifests/expose-spinnaker.yaml
sudo kubectl apply -f /etc/spinnaker/manifests/minio.yaml

######## Bootstrap
sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/start.sh <<-'EOF'
#!/bin/bash
# Determine port detection method
if [[ $(ss -h &> /dev/null; echo $?) -eq 0 ]];
then
  ns_cmd=ss
else
  ns_cmd=netstat
fi

# Wait for Spinnaker to start
while [[ $(${ns_cmd} -plnt | grep 8064 | wc -l) -lt 1 ]];
do
  echo 'Waiting for Halyard daemon to start';
  sleep 2;
done

hal config version edit --version $(cat /home/spinnaker/.hal/version)
sleep 5
hal deploy apply

cat /home/spinnaker/.hal/.secret/public_ip
echo 'admin'
cat /home/spinnaker/.hal/.secret/spinnaker_password
EOF

sudo -u ${SPINUSER} chmod +x /etc/spinnaker/.hal/start.sh

# Start Halyard (TODO turn into daemon)
sudo docker run --name armory-halyard --rm \
    -v /etc/spinnaker/.hal:/home/spinnaker/.hal \
    -v /etc/spinnaker/.kube:/home/spinnaker/.kube \
    -d docker.io/armory/halyard-armory:1.6.4

sudo docker exec -it armory-halyard /home/spinnaker/.hal/start.sh

sudo kubectl get pods -n spinnaker --watch