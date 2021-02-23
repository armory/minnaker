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


function log() {
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  ORANGE='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
  LEVEL=$1
  MSG=$2
  case $LEVEL in
  "INFO") HEADER_COLOR=$GREEN MSG_COLOR=$NS ;;
  "WARN") HEADER_COLOR=$ORANGE MSG_COLOR=$NS ;;
  "KUBE") HEADER_COLOR=$ORANGE MSG_COLOR=$CYAN ;;
  "ERROR") HEADER_COLOR=$RED MSG_COLOR=$NS ;;
  esac
  printf "${HEADER_COLOR}[%-5.5s]${NC} ${MSG_COLOR}%b${NC}" "${LEVEL}" "${MSG}"
  printf "$(date +"%D %T") [%-5.5s] %b" "${LEVEL}" "${MSG}" >>"$OUT"
}

function info() {
  log "INFO" "$1\n"
}

function warn() {
  log "WARN" "$1\n"
}

function error() {
  log "ERROR" "$1\n" && exit 1
}

function handle_generic_kubectl_error() {
  error "Error executing command:\n$ERR_OUTPUT"
}

function exec_kubectl_mutating() {
  log "KUBE" "$1\n"
  ERR_OUTPUT=$({ $1 >>"$OUT"; } 2>&1)
  EXIT_CODE=$?
  [[ $EXIT_CODE != 0 ]] && $2
}

install_k3s () {
  info "--- Installing K3s ---"
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $(cat ${BASE_DIR}/secrets/public_ip)" INSTALL_K3S_VERSION="v1.19.7+k3s1" K3S_KUBECONFIG_MODE="644" sh -
  #curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.19.7+k3s1" K3S_KUBECONFIG_MODE=644 sh -
  info " --- END K3s --- "
}

install_yq () {
  info "Installing yq"
  sudo curl -sfL https://github.com/mikefarah/yq/releases/download/3.4.1/yq_linux_amd64 -o /usr/local/bin/yq
  sudo chmod +x /usr/local/bin/yq
  if [[ ! -e "/usr/local/bin/yq" ]]; then
    error "failed to install yq - please manually install https://github.com/mikefarah/yq/"
    exit 1
  fi
}

install_jq () {
info "Installing jq"

# install prereqs jq
# if jq is not installed
if ! jq --help > /dev/null 2>&1; then
  # only try installing if a Debian system
  if apt-get -v > /dev/null 2>&1; then 
    info "Using apt-get to install jq"
    sudo apt-get update && sudo apt-get install -y jq
  else
    error "ERROR: Unsupported OS! Cannot automatically install jq. Please try install jq first before rerunning this script"
    exit 2
  fi
fi
}

detect_endpoint () {
  info "Trying to detect endpoint"
  if [[ ! -s ${BASE_DIR}/secrets/public_ip || -n "$1" ]]; then
    if [[ -n "${PUBLIC_IP}" ]]; then
      info "Using provided public IP ${PUBLIC_IP}"
      echo "${PUBLIC_IP}" > ${BASE_DIR}/secrets/public_ip
    else 
      if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
        # change to ask AWS public metadata? http://169.254.169.254/latest/meta-data/public_ipv4
        #rm ${BASE_DIR}/secrets/public_ip
        #while [[ ! -s ${BASE_DIR}/secrets/public_ip ]]; do
        info "Detected cloud metadata endpoint"
        info "Trying to determine public IP address (using 'curl -m http://169.254.169.254/latest/meta-data/public-ipv4')"
        info "IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 | tee ${BASE_DIR}/secrets/public_ip)"
        #  info "Trying to determine public IP address (using 'dig +short TXT o-o.myaddr.l.google.com @ns1.google.com')"
        #  dig +short TXT o-o.myaddr.l.google.com @ns1.google.com | sed 's|"||g' | tee ${BASE_DIR}/secrets/public_ip
        #done
      else
        info "No cloud metadata endpoint detected, detecting interface IP (and storing in ${BASE_DIR}/secrets/public_ip): $(ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee ${BASE_DIR}/secrets/public_ip)"
      fi
    fi
  else
    info "Using existing Public IP from ${BASE_DIR}/secrets/public_ip"
    cat ${BASE_DIR}/secrets/public_ip
  fi
}

update_endpoint () {
  #PUBLIC_ENDPOINT="spinnaker.$(cat "${BASE_DIR}/secrets/public_ip").nip.io"   # use nip.io which is a DNS that will always resolve.
  PUBLIC_ENDPOINT="$(cat "${BASE_DIR}/secrets/public_ip")" 

  info "Updating spinsvc templates with new endpoint: ${PUBLIC_ENDPOINT}"
  #yq w -i ${BASE_DIR}/expose/ingress-traefik.yml spec.rules[0].host ${PUBLIC_ENDPOINT}
  yq d -i ${BASE_DIR}/expose/ingress-traefik.yml spec.rules[0].host
  yq w -i ${BASE_DIR}/expose/patch-urls.yml spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl https://${PUBLIC_ENDPOINT}
  yq w -i ${BASE_DIR}/expose/patch-urls.yml spec.spinnakerConfig.config.security.apiSecurity.overrideBaseUrl  https://${PUBLIC_ENDPOINT}/api
  yq w -i ${BASE_DIR}/expose/patch-urls.yml spec.spinnakerConfig.config.security.apiSecurity.corsAccessPattern  https://${PUBLIC_ENDPOINT}
}

generate_passwords () {
  # for PASSWORD_ITEM in spinnaker_password minio_password mysql_password; do
  for PASSWORD_ITEM in spinnaker_password; do
    if [[ ! -s ${BASE_DIR}/secrets/${PASSWORD_ITEM} ]]; then
      info "Generating password [${BASE_DIR}/secrets/${PASSWORD_ITEM}]:"
      openssl rand -base64 36 | tee ${BASE_DIR}/secrets/${PASSWORD_ITEM}
    else
      warn "Password already exists: [${BASE_DIR}/secrets/${PASSWORD_ITEM}]"
    fi
  done
  
  SPINNAKER_PASSWORD=$(cat "${BASE_DIR}/secrets/spinnaker_password")
}

# copy_templates () {
#   # Directory structure:
#   ## BASE_DIR/templates/manifests/*: will by hydrated locally, conditionally copied to BASE_DIR/manifests
#   ## BASE_DIR/templates/profiles/*: will be hydrated locally, conditionally copied to BASE_DIR/.hal/default/profiles
#   ## BASE_DIR/templates/service-settings/*: will be hydrated locally, conditionally copied to BASE_DIR/.hal/default/service-settings
#   ## BASE_DIR/templates/config: will be hydrated locally, conditionally copied to BASE_DIR/.hal/config
#   cp -rpv ${PROJECT_DIR}/templates/manifests ${BASE_DIR}/templates/
  
#   cp -rpv ${PROJECT_DIR}/templates/profiles ${BASE_DIR}/templates/
#   cp -rpv ${PROJECT_DIR}/templates/service-settings ${BASE_DIR}/templates/

#   cp ${PROJECT_DIR}/templates/config ${BASE_DIR}/templates/
#   if [[ ${OPEN_SOURCE} -eq 0 ]]; then
#     cat ${PROJECT_DIR}/templates/config-armory >> ${BASE_DIR}/templates/config
#   fi
# }

update_templates_for_auth () {
  for f in $(ls -1 ${PROJECT_DIR}/templates/profiles-auth/); do
    cat ${PROJECT_DIR}/templates/profiles-auth/${f} | tee -a ${BASE_DIR}/templates/profiles/${f}
  done
}

hydrate_templates () {
  sed -i "s|^http-password=.*|http-password=${SPINNAKER_PASSWORD}|g" ${BASE_DIR}/secrets/secrets-example.env
  #sed -i "s|username2replace|admin|g" security/patch-basic-auth.yml
  yq w -i ${BASE_DIR}/security/patch-basic-auth.yml spec.spinnakerConfig.profiles.gate.spring.security.user.name admin
  #sed -i -r "s|(^.*)version: .*|\1version: ${VERSION}|" core_config/patch-version.yml
  yq w -i ${BASE_DIR}/core_config/patch-version.yml spec.spinnakerConfig.config.version ${VERSION}
  sed -i "s|token|# token|g" accounts/git/patch-github.yml
  sed -i "s|username|# username|g" accounts/git/patch-gitrepo.yml
  sed -i "s|token|# token|g" accounts/git/patch-gitrepo.yml

  if [[ ${OPEN_SOURCE} -eq 0 ]]; then
    sed -i "s|xxxxxxxx-.*|${MAGIC_NUMBER}$(uuidgen | cut -c 9-)|" armory/patch-diagnostics.yml
    sed -i "s|#- armory|- armory|g" kustomization.yml
  else
    # remove armory related patches
    sed -i "s|- armory|#- armory|g" kustomization.yml
  fi
}

## Not necessary anymore - using yq and kustomize
# # The primary difference is i.bak, cause OSX sed is stupid
# hydrate_templates_osx () {
#   PUBLIC_ENDPOINT=$(cat ${BASE_DIR}/secrets/public_ip)

#   # TODO: Decide whether to replace with find | xargs sed
#   # TODO: Fix the sed i.bak, collapse with hydrate_templates
#   for f in ${BASE_DIR}/templates/config ${BASE_DIR}/templates/{manifests,profiles,service-settings}/*; do
#     sed -i.bak \
#       -e "s|NAMESPACE|${NAMESPACE}|g" \
#       -e "s|BASE_DIR|${BASE_DIR}|g" \
#       -e "s|HALYARD_IMAGE|${HALYARD_IMAGE}|g" \
#       -e "s|PUBLIC_ENDPOINT|${PUBLIC_ENDPOINT}|g" \
#       -e "s|uuid.*|uuid: ${MAGIC_NUMBER}$(uuidgen | cut -c 9-)|g" \
#       ${f}
#     rm ${f}.bak
#   done
# }

# conditional_copy () {
#   ## BASE_DIR/templates/manifests/* conditionally copied to BASE_DIR/manifests
#   ## BASE_DIR/templates/profiles/* conditionally copied to BASE_DIR/.hal/default/profiles
#   ## BASE_DIR/templates/service-settings/* conditionally copied to BASE_DIR/.hal/default/service-settings
#   ## BASE_DIR/templates/config conditionally copied to BASE_DIR/.hal/config
#   for f in $(ls -1 ${BASE_DIR}/templates/manifests/); do
#     if [[ ! -e ${BASE_DIR}/manifests/${f} ]]; then
#       cp ${BASE_DIR}/templates/manifests/${f} ${BASE_DIR}/manifests/
#     fi
#   done

#   for f in $(ls -1 ${BASE_DIR}/templates/profiles/); do
#     if [[ ! -e ${BASE_DIR}/.hal/default/profiles/${f} ]]; then
#       cp ${BASE_DIR}/templates/profiles/${f} ${BASE_DIR}/.hal/default/profiles/
#     fi
#   done

#   for f in $(ls -1 ${BASE_DIR}/templates/service-settings/); do
#     if [[ ! -e ${BASE_DIR}/.hal/default/service-settings/${f} ]]; then
#       cp ${BASE_DIR}/templates/service-settings/${f} ${BASE_DIR}/.hal/default/service-settings/
#     fi
#   done

#   if [[ ! -e ${BASE_DIR}/.hal/config ]]; then
#     cp ${BASE_DIR}/templates/config ${BASE_DIR}/.hal/
#   fi
# }

# create_hal_shortcut () {
# sudo tee /usr/local/bin/hal <<-'EOF'
# #!/bin/bash
# POD_NAME=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)
# # echo $POD_NAME
# set -x
# kubectl -n spinnaker exec -i ${POD_NAME} -- sh -c "hal $*"
# EOF
# sudo chmod 755 /usr/local/bin/hal
# }

create_spin_endpoint () {

info "Creating spin_endpoint helper function"

sudo tee /usr/local/bin/spin_endpoint <<-'EOF'
#!/bin/bash
#echo "$(kubectl get spinsvc spinnaker -n spinnaker -ojsonpath='{.spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl}')"
echo "$(yq r BASE_DIR/expose/patch-urls.yml spec.spinnakerConfig.config.security.uiSecurity.overrideBaseUrl)"
[[ -f BASE_DIR/secrets/spinnaker_password ]] && echo "username: 'admin'"
[[ -f BASE_DIR/secrets/spinnaker_password ]] && echo "password: '$(cat BASE_DIR/secrets/spinnaker_password)'"
EOF
sudo chmod 755 /usr/local/bin/spin_endpoint

sudo sed -i "s|BASE_DIR|${BASE_DIR}|g" /usr/local/bin/spin_endpoint
}

restart_k3s (){
  info "Restarting k3s"
  /usr/local/bin/k3s-killall.sh
  sudo systemctl restart k3s
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
