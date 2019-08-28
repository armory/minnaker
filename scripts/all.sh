#!/bin/bash
set -x
set -e

##### Functions
install_k3s () {
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy=traefik" sh -
}

get_ips () {
  if [[ ! -f /etc/spinnaker/.hal/private_ip ]]; then
    echo "Detecting Private IP (and storing in /etc/spinnaker/.hal/private_ip):"
    ip r get 8.8.8.8 | awk 'NR==1{print $NF}' | sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/private_ip
  else
    echo "Using existing Private IP from /etc/spinnaker/.hal/private_ip"
    cat /etc/spinnaker/.hal/private_ip
  fi

  if [[ ! -f /etc/spinnaker/.hal/public_ip ]]; then
    if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
      echo "Detected cloud metadata endpoint; Detecting Public IP Address from ifconfig.co (and storing in /etc/spinnaker/.hal/public_ip):"
      curl -sSfL ifconfig.co | sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/public_ip
    else
      echo "No cloud metadata endpoint detected, using private IP for public IP (and storing in /etc/spinnaker/.hal/public_ip):"
      sudo -u ${SPINUSER} cp -rp /etc/spinnaker/.hal/private_ip \
          /etc/spinnaker/.hal/public_ip
      cat /etc/spinnaker/.hal/public_ip
    fi
  else
    echo "Using existing Private IP from /etc/spinnaker/.hal/public_ip"
    cat /etc/spinnaker/.hal/public_ip
  fi
}

generate_passwords () {
  if [[ ! -f /etc/spinnaker/.hal/.secret/minio_password ]]; then
    echo "Generating Minio password (/etc/spinnaker/.hal/.secret/minio_password):"
    openssl rand -base64 32 | sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/minio_password
  else
    echo "Minio password already exists (/etc/spinnaker/.hal/.secret/minio_password)"
  fi

  if [[ ! -f /etc/spinnaker/.hal/.secret/spinnaker_password ]]; then
    echo "Generating Spinnaker password (/etc/spinnaker/.hal/.secret/spinnaker_password):"
    openssl rand -base64 32 | sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/.secret/spinnaker_password
  else
    echo "Spinnaker password already exists (/etc/spinnaker/.hal/.secret/spinnaker_password)"
  fi
}

print_templates () {
sudo -u ${SPINUSER} tee /etc/spinnaker/templates/minio.yaml <<-'EOF'
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

sudo -u ${SPINUSER} tee /etc/spinnaker/templates/config-seed <<-'EOF'
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

sudo -u ${SPINUSER} tee /etc/spinnaker/templates/gate-local.yml <<-EOF
security:
  basicform:
    enabled: true
  user:
    name: admin
    password: SPINNAKER_PASSWORD
EOF
}

print_manifests () {
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
}

print_bootstrap_script () {
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

VERSION=$(hal version latest -q)

hal config version edit --version ${VERSION}
sleep 5
hal deploy apply

cat /home/spinnaker/.hal/public_ip
echo 'admin'
cat /home/spinnaker/.hal/.secret/spinnaker_password
EOF
}

# Todo: Support multiple installation methods (apt, etc.)
install_git () {
  set +e
  if [[ $(command -v snap >/dev/null; echo $?) -eq 0 ]];
  then
    snap install git
  else
    sudo apt-get install git -y
  fi
  set -e
}

# Todo: Support multiple installation methods (apt, etc.)
install_docker () {
  set +e
  if [[ $(command -v snap >/dev/null; echo $?) -eq 0 ]];
  then
    snap install docker
  else
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io
  fi
  set -e
}

########## Script starts here
# TODO paramaterize
VERSION=2.15.2
# Armory Halyard uses 100; OSS Halyard uses 1000
SPINUSER=$(id -u 100 -n)

# Scaffold out directories
sudo mkdir -p /etc/spinnaker/{.hal/.secret,.hal/default/profiles,.kube,manifests,tools,templates}
sudo chown -R ${SPINUSER} /etc/spinnaker

# Install k3s
install_k3s

# Install git and Docker
install_git
install_docker

# Install Metrics server
sudo -u ${SPINUSER} git clone https://github.com/kubernetes-incubator/metrics-server.git /etc/spinnaker/manifests/metrics-server
sudo kubectl apply -f /etc/spinnaker/manifests/metrics-server/deploy/1.8+/

get_ips
generate_passwords
print_templates
print_manifests

# Populate (static) front50-local.yaml if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/front50-local.yml ]];
then
sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/default/profiles/front50-local.yml <<-'EOF'
spinnaker.s3.versioning: false
EOF
fi

# Populate (static) settings-local.js if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/settings-local.js];
then
sudo -u ${SPINUSER} tee /etc/spinnaker/.hal/default/profiles/settings-local.js <<-EOF
window.spinnakerSettings.authEnabled = true;
EOF
fi

# Hydrate (dynamic) gate-local.yml with password if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/gate-local.yml ]];
then
  sed "s|SPINNAKER_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)|g" \
    /etc/spinnaker/templates/gate-local.yaml \
    > sudo -u ${SPINUSER} tee  /etc/spinnaker/.hal/default/profiles/gate-local.yml
fi

# Hydrate (dynamic) config seed with minio password and public IP
sudo -u ${SPINUSER} sed \
    -e "s|MINIO_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/minio_password)|g" \
    -e "s|PUBLIC_IP|$(cat /etc/spinnaker/.hal/public_ip)|g" \
    /etc/spinnaker/templates/config-seed > /etc/spinnaker/.hal/config-seed

# Seed config if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/config ]]; then
  sudo -u ${SPINUSER} cp /etc/spinnaker/.hal/config-seed /etc/spinnaker/.hal/config
fi

# Populate minio manifest if it doesn't exist
if [[ ! -e /etc/spinnaker/manifests/minio.yaml ]];
then
  sed "s|PASSWORD|$(cat /etc/spinnaker/.hal/.secret/minio_password)|g" \
    /etc/spinnaker/templates/minio.yaml \
    > sudo -u ${SPINUSER} tee /etc/spinnaker/templates/minio.yaml
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

sudo -u ${SPINUSER} chmod +x /etc/spinnaker/.hal/start.sh

# Start Halyard (TODO turn into daemon)
sudo docker run --name armory-halyard --rm \
    -v /etc/spinnaker/.hal:/home/spinnaker/.hal \
    -v /etc/spinnaker/.kube:/home/spinnaker/.kube \
    -d docker.io/armory/halyard-armory:1.6.4

sudo docker exec -it armory-halyard /home/spinnaker/.hal/start.sh

sudo kubectl get pods -n spinnaker --watch
