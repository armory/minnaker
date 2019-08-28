#!/bin/bash
set -x
set -e

##### Functions
install_k3s () {
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--no-deploy=traefik" K3S_KUBECONFIG_MODE=644 sh -
}

detect_ips () {
  if [[ ! -f /etc/spinnaker/.hal/private_ip ]]; then
    echo "Detecting Private IP (and storing in /etc/spinnaker/.hal/private_ip):"
    # Need a better way of getting this.
    ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee /etc/spinnaker/.hal/private_ip
  else
    echo "Using existing Private IP from /etc/spinnaker/.hal/private_ip"
    cat /etc/spinnaker/.hal/private_ip
  fi

  if [[ ! -f /etc/spinnaker/.hal/public_ip ]]; then
    if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
      echo "Detected cloud metadata endpoint; Detecting Public IP Address from ifconfig.co (and storing in /etc/spinnaker/.hal/public_ip):"
      curl -sSfL ifconfig.co | tee /etc/spinnaker/.hal/public_ip
    else
      echo "No cloud metadata endpoint detected, using private IP for public IP (and storing in /etc/spinnaker/.hal/public_ip):"
      cp -rp /etc/spinnaker/.hal/private_ip \
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
    openssl rand -base64 32 | tee /etc/spinnaker/.hal/.secret/minio_password
  else
    echo "Minio password already exists (/etc/spinnaker/.hal/.secret/minio_password)"
  fi

  if [[ ! -f /etc/spinnaker/.hal/.secret/spinnaker_password ]]; then
    echo "Generating Spinnaker password (/etc/spinnaker/.hal/.secret/spinnaker_password):"
    openssl rand -base64 32 | tee /etc/spinnaker/.hal/.secret/spinnaker_password
  else
    echo "Spinnaker password already exists (/etc/spinnaker/.hal/.secret/spinnaker_password)"
  fi
}

print_templates () {
tee /etc/spinnaker/manifests/halyard.yaml <<-'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  name: spinnaker
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: halyard
  namespace: spinnaker
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: halyard
    spec:
      containers:
      - name: halyard
        image: armory/halyard-armory:1.6.4
        volumeMounts:
        - name: hal
          mountPath: "/home/spinnaker/.hal"
        - name: kube
          mountPath: "/home/spinnaker/.kube"
        env:
        - name: HOME
          value: "/home/spinnaker"
      securityContext:
        runAsUser: 1000
        runAsGroup: 65535
      volumes:
      - name: hal
        hostPath:
          path: /etc/spinnaker/.hal
          type: DirectoryOrCreate
      - name: kube
        hostPath:
          path: /etc/spinnaker/.kube
          type: DirectoryOrCreate
EOF

tee /etc/spinnaker/templates/minio.yaml <<-'EOF'
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
        - name: storage
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

tee /etc/spinnaker/templates/config-seed <<-'EOF'
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

tee /etc/spinnaker/templates/gate-local.yml <<-EOF
security:
  basicform:
    enabled: true
  user:
    name: admin
    password: SPINNAKER_PASSWORD
EOF
}

print_manifests () {
tee /etc/spinnaker/manifests/expose-spinnaker.yaml <<-'EOF'
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

get_metrics_server_manifest () {
# TODO: detect existence and skip if existing
  rm -rf /etc/spinnaker/manifests/metrics-server
  git clone https://github.com/kubernetes-incubator/metrics-server.git /etc/spinnaker/manifests/metrics-server
}

print_bootstrap_script () {
tee /etc/spinnaker/.hal/start.sh <<-'EOF'
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

echo ""
echo "Installing Spinnaker - this may take a while (up to 10 minutes) on slower machines"
echo ""

hal deploy apply --wait-for-completion

echo "http://$(cat /home/spinnaker/.hal/public_ip)"
echo "username: 'admin'"
echo "password: '$(cat /home/spinnaker/.hal/.secret/spinnaker_password)'"
EOF
  
  chmod +x /etc/spinnaker/.hal/start.sh
# sudo -u ${SPINUSER} chmod +x /etc/spinnaker/.hal/start.sh
}

# Todo: Support multiple installation methods (apt, etc.)
install_git () {
  set +e
  if [[ $(command -v snap >/dev/null; echo $?) -eq 0 ]];
  then
    snap install git
  elif [[ $(command -v apt-get >/dev/null; echo $?) -eq 0 ]];
  then
    sudo apt-get install git -y
  else
    sudo yum install git -y
  fi
  set -e
}

populate_profiles () {
# Populate (static) front50-local.yaml if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/front50-local.yml ]];
then
tee /etc/spinnaker/.hal/default/profiles/front50-local.yml <<-'EOF'
spinnaker.s3.versioning: false
EOF
fi

# Populate (static) settings-local.js if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/settings-local.js ]];
then
tee /etc/spinnaker/.hal/default/profiles/settings-local.js <<-EOF
window.spinnakerSettings.authEnabled = true;
EOF
fi

# Hydrate (dynamic) gate-local.yml with password if it doesn't exist
if [[ ! -e /etc/spinnaker/.hal/default/profiles/gate-local.yml ]];
then
  sed "s|SPINNAKER_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)|g" \
    /etc/spinnaker/templates/gate-local.yml \
    | tee /etc/spinnaker/.hal/default/profiles/gate-local.yml
fi
}

create_kubernetes_creds () {
  curl -L https://github.com/armory/spinnaker-tools/releases/download/0.0.6/spinnaker-tools-linux \
      -o /etc/spinnaker/tools/spinnaker-tools

  chmod +x /etc/spinnaker/tools/spinnaker-tools

  /etc/spinnaker/tools/spinnaker-tools create-service-account \
      -c default \
      -i /etc/rancher/k3s/k3s.yaml \
      -o /etc/spinnaker/.kube/localhost-config \
      -n spinnaker \
      -s spinnaker-sa

  sudo chown 1000 /etc/spinnaker/.kube/localhost-config

  sed "s/localhost/$(cat /etc/spinnaker/.hal/private_ip)/g" \
      /etc/spinnaker/.kube/localhost-config \
      | tee /etc/spinnaker/.kube/config

  cp -rpv /etc/spinnaker/.kube/config \
      /etc/spinnaker/.hal/.secret/kubeconfig-spinnaker-sa
}

populate_minio_manifest () {
  # Populate minio manifest if it doesn't exist
  if [[ ! -e /etc/spinnaker/manifests/minio.yaml ]];
  then
    sed "s|PASSWORD|$(cat /etc/spinnaker/.hal/.secret/minio_password)|g" \
      /etc/spinnaker/templates/minio.yaml \
      | tee /etc/spinnaker/manifests/minio.yaml
  fi
}

seed_halconfig () {
  # Hydrate (dynamic) config seed with minio password and public IP
  sed \
    -e "s|MINIO_PASSWORD|$(cat /etc/spinnaker/.hal/.secret/minio_password)|g" \
    -e "s|PUBLIC_IP|$(cat /etc/spinnaker/.hal/public_ip)|g" \
    /etc/spinnaker/templates/config-seed \
    | tee /etc/spinnaker/.hal/config-seed

  # Seed config if it doesn't exist
  if [[ ! -e /etc/spinnaker/.hal/config ]]; then
    cp /etc/spinnaker/.hal/config-seed /etc/spinnaker/.hal/config
  fi
}

create_hal_shortcut () {
sudo tee /usr/local/bin/hal <<-'EOF'
#!/bin/bash
POD_NAME=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)
# echo $POD_NAME
set -x
kubectl -n spinnaker exec -it ${POD_NAME} hal $@
EOF

sudo chmod 755 /usr/local/bin/hal
}

##### Script starts here

# Scaffold out directories
# OSS Halyard uses 1000; we're using 1000 for everything
sudo mkdir -p /etc/spinnaker/{.hal/.secret,.hal/default/profiles,.kube,manifests,tools,templates}
sudo chown -R 1000 /etc/spinnaker

install_k3s
install_git

get_metrics_server_manifest
detect_ips
generate_passwords
print_templates
print_manifests
print_bootstrap_script
populate_profiles
populate_minio_manifest
seed_halconfig
create_kubernetes_creds

# Install Minio and service

# Need sudo here cause the kubeconfig is owned by root with 644
sudo kubectl config set-context default --namespace spinnaker
kubectl apply -f /etc/spinnaker/manifests/metrics-server/deploy/1.8+/
kubectl apply -f /etc/spinnaker/manifests/expose-spinnaker.yaml
kubectl apply -f /etc/spinnaker/manifests/minio.yaml
kubectl apply -f /etc/spinnaker/manifests/halyard.yaml

######## Bootstrap

while [[ $(kubectl get deployment -n spinnaker halyard -ojsonpath='{.status.availableReplicas}') -ne 1 ]];
do
echo "Waiting for Halyard pod to start"
sleep 2;
done

sleep 5;
HALYARD_POD=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f2)
kubectl -n spinnaker exec -it ${HALYARD_POD} /home/spinnaker/.hal/start.sh

create_hal_shortcut