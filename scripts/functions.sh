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

ARMORY_HALYARD_IMAGE="armory/halyard-armory:1.9.4"

install_k3s () {
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $(cat ${BASE_DIR}/.hal/public_endpoint)" INSTALL_K3S_VERSION="v1.17.4+k3s1" K3S_KUBECONFIG_MODE=644 sh -
}

install_yq () {
  sudo curl -sfL https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64 -o /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
}

detect_endpoint () {
  if [[ ! -s ${BASE_DIR}/.hal/public_endpoint ]]; then
    if [[ -n "${PUBLIC_ENDPOINT}" ]]; then
      echo "Using provided public IP ${PUBLIC_ENDPOINT}"
      echo "${PUBLIC_ENDPOINT}" > ${BASE_DIR}/.hal/public_endpoint
      touch ${BASE_DIR}/.hal/public_endpoint_provided
    else
      if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
        while [[ ! -s ${BASE_DIR}/.hal/public_endpoint ]]; do
          echo "Detected cloud metadata endpoint"
          echo "Trying to determine public IP address (using 'dig +short TXT o-o.myaddr.l.google.com @ns1.google.com')"
          sleep 1
          dig +short TXT o-o.myaddr.l.google.com @ns1.google.com | sed 's|"||g' | tee ${BASE_DIR}/.hal/public_endpoint
        done
      else
        echo "No cloud metadata endpoint detected, detecting interface IP (and storing in ${BASE_DIR}/.hal/public_endpoint):"
        ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee ${BASE_DIR}/.hal/public_endpoint
        cat ${BASE_DIR}/.hal/public_endpoint
      fi
    fi
  else
    echo "Using existing Public IP from ${BASE_DIR}/.hal/public_endpoint"
    cat ${BASE_DIR}/.hal/public_endpoint
  fi
}

generate_passwords () {
  # for PASSWORD_ITEM in spinnaker_password minio_password mysql_password; do
  for PASSWORD_ITEM in spinnaker_password; do
    if [[ ! -s ${BASE_DIR}/.hal/.secret/${PASSWORD_ITEM} ]]; then
      echo "Generating password [${BASE_DIR}/.hal/.secret/${PASSWORD_ITEM}]:"
      openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/${PASSWORD_ITEM}
    else
      echo "Password already exists: [${BASE_DIR}/.hal/.secret/${PASSWORD_ITEM}]"
    fi
  done
}

copy_templates () {
  # Directory structure:
  ## BASE_DIR/templates/manifests/*: will by hydrated locally, conditionally copied to BASE_DIR/manifests
  ## BASE_DIR/templates/profiles/*: will be hydrated locally, conditionally copied to BASE_DIR/.hal/default/profiles
  ## BASE_DIR/templates/service-settings/*: will be hydrated locally, conditionally copied to BASE_DIR/.hal/default/service-settings
  ## BASE_DIR/templates/config: will be hydrated locally, conditionally copied to BASE_DIR/.hal/config
  cp -rpv ${PROJECT_DIR}/templates/manifests ${BASE_DIR}/templates/
  
  cp -rpv ${PROJECT_DIR}/templates/profiles ${BASE_DIR}/templates/
  cp -rpv ${PROJECT_DIR}/templates/service-settings ${BASE_DIR}/templates/

  cp ${PROJECT_DIR}/templates/config ${BASE_DIR}/templates/
  if [[ ${OPEN_SOURCE} -eq 0 ]]; then
    cat ${PROJECT_DIR}/templates/config-armory >> ${BASE_DIR}/templates/config
  fi
}

update_templates_for_auth () {
  for f in $(ls -1 ${PROJECT_DIR}/templates/profiles-auth/); do
    cat ${PROJECT_DIR}/templates/profiles-auth/${f} | tee -a ${BASE_DIR}/templates/profiles/${f}
  done
}

hydrate_templates () {
  PUBLIC_ENDPOINT=$(cat ${BASE_DIR}/.hal/public_endpoint)
  # If no generate_passwords was run, use "password" (there should also be no placeholders so no actual substitution)
  if [[ -f ${BASE_DIR}/.hal/.secret/spinnaker_password ]]; then
    SPINNAKER_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/spinnaker_password)
  else
    SPINNAKER_PASSWORD="password"
  fi
  
  # Todo: Decide whether to use these
  # MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)
  #       -e "s|MINIO_PASSWORD|${MINIO_PASSWORD}|g" \
  # MYSQL_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/mysql_password)
  #       -e "s|MYSQL_PASSWORD|${MYSQL_PASSWORD}|g" \

  # TODO: Decide whether to replace with find | xargs sed
  for f in ${BASE_DIR}/templates/config ${BASE_DIR}/templates/{manifests,profiles,service-settings}/*; do
    sed -i \
      -e "s|NAMESPACE|${NAMESPACE}|g" \
      -e "s|BASE_DIR|${BASE_DIR}|g" \
      -e "s|HALYARD_IMAGE|${HALYARD_IMAGE}|g" \
      -e "s|PUBLIC_ENDPOINT|${PUBLIC_ENDPOINT}|g" \
      -e "s|SPINNAKER_PASSWORD|${SPINNAKER_PASSWORD}|g" \
      -e "s|uuid.*|uuid: ${MAGIC_NUMBER}$(uuidgen | cut -c 9-)|g" \
      ${f}
  done
}

# The primary difference is i.bak, cause OSX sed is stupid
hydrate_templates_osx () {
  PUBLIC_ENDPOINT=$(cat ${BASE_DIR}/.hal/public_endpoint)

  # TODO: Decide whether to replace with find | xargs sed
  # TODO: Fix the sed i.bak, collapse with hydrate_templates
  for f in ${BASE_DIR}/templates/config ${BASE_DIR}/templates/{manifests,profiles,service-settings}/*; do
    sed -i.bak \
      -e "s|NAMESPACE|${NAMESPACE}|g" \
      -e "s|BASE_DIR|${BASE_DIR}|g" \
      -e "s|HALYARD_IMAGE|${HALYARD_IMAGE}|g" \
      -e "s|PUBLIC_ENDPOINT|${PUBLIC_ENDPOINT}|g" \
      -e "s|uuid.*|uuid: ${MAGIC_NUMBER}$(uuidgen | cut -c 9-)|g" \
      ${f}
    rm ${f}.bak
  done
}

conditional_copy () {
  ## BASE_DIR/templates/manifests/* conditionally copied to BASE_DIR/manifests
  ## BASE_DIR/templates/profiles/* conditionally copied to BASE_DIR/.hal/default/profiles
  ## BASE_DIR/templates/service-settings/* conditionally copied to BASE_DIR/.hal/default/service-settings
  ## BASE_DIR/templates/config conditionally copied to BASE_DIR/.hal/config
  for f in $(ls -1 ${BASE_DIR}/templates/manifests/); do
    if [[ ! -e ${BASE_DIR}/manifests/${f} ]]; then
      cp ${BASE_DIR}/templates/manifests/${f} ${BASE_DIR}/manifests/
    fi
  done

  for f in $(ls -1 ${BASE_DIR}/templates/profiles/); do
    if [[ ! -e ${BASE_DIR}/.hal/default/profiles/${f} ]]; then
      cp ${BASE_DIR}/templates/profiles/${f} ${BASE_DIR}/.hal/default/profiles/
    fi
  done

  for f in $(ls -1 ${BASE_DIR}/templates/service-settings/); do
    if [[ ! -e ${BASE_DIR}/.hal/default/service-settings/${f} ]]; then
      cp ${BASE_DIR}/templates/service-settings/${f} ${BASE_DIR}/.hal/default/service-settings/
    fi
  done

  if [[ ! -e ${BASE_DIR}/.hal/config ]]; then
    cp ${BASE_DIR}/templates/config ${BASE_DIR}/.hal/
  fi
}

create_hal_shortcut () {
sudo tee /usr/local/bin/hal <<-'EOF'
#!/bin/bash
POD_NAME=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)
# echo $POD_NAME
set -x
kubectl -n spinnaker exec -i ${POD_NAME} -- sh -c "hal $*"
EOF

sudo chmod 755 /usr/local/bin/hal
}

create_spin_endpoint () {
sudo tee /usr/local/bin/spin_endpoint <<-'EOF'
#!/bin/bash
yq r /etc/spinnaker/.hal/config deploymentConfigurations[0].security.uiSecurity.overrideBaseUrl
[[ -f /etc/spinnaker/.hal/.secret/spinnaker_password ]] && echo "username: 'admin'"
[[ -f /etc/spinnaker/.hal/.secret/spinnaker_password ]] && echo "password: '$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)'"
EOF

sudo chmod 755 /usr/local/bin/spin_endpoint
}

####### These are not currently used

install_git () {
  set +e
  if [[ $(command -v snap >/dev/null; echo $?) -eq 0 ]];
  then
    sudo snap install git
  elif [[ $(command -v apt-get >/dev/null; echo $?) -eq 0 ]];
  then
    sudo apt-get install git -y
  else
    sudo yum install git -y
  fi
  set -e
}

get_metrics_server_manifest () {
# TODO: detect existence and skip if existing
  rm -rf ${BASE_DIR}/manifests/metrics-server
  git clone https://github.com/kubernetes-incubator/metrics-server.git ${BASE_DIR}/metrics-server
}
