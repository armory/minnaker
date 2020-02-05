#!/bin/bash
set -x
set -e

# Not (currently) designed for OSX

# This is used to 'reset' a Minnaker instance.  It regenerates the Minio and Gate passwords
# Also, it will do the following with the public endpoint:
# # If a new public endpoint is provided (with the flag -P), then the new endpoint will be used
# # Otherwise, if the previous public endpoint was provided was a flag, that endpoint will be used
# # Otherwise, the public endpoint will be re-detected

##### Functions
print_help () {
  set +x
  echo "Usage: refresh_endpoint.sh"
  echo "               [-P|--public-endpoint <PUBLIC_IP_OR_DNS_ADDRESS>]  : Specify public IP (or DNS name) for instance (rather than detecting using ifconfig.co)"
  set -x
}

detect_endpoint () {
  if [[ -n "${PUBLIC_ENDPOINT}" ]]; then
    echo "Using provided public endpoint ${PUBLIC_ENDPOINT}"
    echo "${PUBLIC_ENDPOINT}" > ${BASE_DIR}/.hal/public_endpoint
    touch ${BASE_DIR}/.hal/public_endpoint_provided
  elif [[ ! -f ${BASE_DIR}/.hal/public_endpoint_provided ]]; then
    if [[ $(curl -m 1 169.254.169.254 -sSfL &>/dev/null; echo $?) -eq 0 ]]; then
      # Remove the entry
      >${BASE_DIR}/.hal/public_endpoint
      while [[ ! -f ${BASE_DIR}/.hal/public_endpoint || $(wc -l < ${BASE_DIR}/.hal/public_endpoint) -eq 0 ]]; do
        echo "Detected cloud metadata endpoint; Detecting Public IP Address from ifconfig.co (and storing in ${BASE_DIR}/.hal/public_endpoint):"
        sleep 1
        curl -sSfL ifconfig.co | tee ${BASE_DIR}/.hal/public_endpoint
      done
    else
      echo "No cloud metadata endpoint detected, detecting interface IP (and storing in ${BASE_DIR}/.hal/public_endpoint):"
      ip r get 8.8.8.8 | awk 'NR==1{print $7}' | tee ${BASE_DIR}/.hal/public_endpoint
      cat ${BASE_DIR}/.hal/public_endpoint
    fi
  else
    echo "Using previously defined public endpoint $(cat ${BASE_DIR}/.hal/public_endpoint)"
  fi
}

update_endpoint () {
  ENDPOINT=$(cat ${BASE_DIR}/.hal/public_endpoint)
  yq w -i ${BASE_DIR}/.hal/config deploymentConfigurations[0].security.uiSecurity.overrideBaseUrl https://${ENDPOINT}
  yq w -i ${BASE_DIR}/.hal/config deploymentConfigurations[0].security.apiSecurity.overrideBaseUrl  https://${ENDPOINT}/api/v1
}

apply_changes () {
  while [[ $(kubectl get statefulset -n spinnaker halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
  do
    echo "Waiting for Halyard pod to start"
    sleep 2;
  done

  # We do this twice, because for some reason Kubernetes sometimes reports pods as healthy on first start after a reboot
  sleep 15

  while [[ $(kubectl get statefulset -n spinnaker halyard -ojsonpath='{.status.readyReplicas}') -ne 1 ]];
  do
    echo "Waiting for Halyard pod to start"
    sleep 2;
  done

  kubectl -n spinnaker exec -i halyard-0 -- hal deploy apply
}

PUBLIC_ENDPOINT=""
BASE_DIR=/etc/spinnaker

while [ "$#" -gt 0 ]; do
  case "$1" in
    -P|--public-endpoint)
      if [ -n $2 ]; then
        PUBLIC_ENDPOINT=$2
        shift
      else
        printf "Error: --public-endpoint requires an IP address >&2"
        exit 1
      fi
      ;;
    -B|--base-dir)
      if [ -n $2 ]; then
        BASE_DIR=$2
      else
        printf "Error: --base-dir requires a directory >&2"
        exit 1
      fi
      ;;
    -h|--help)
      print_help
      exit 1
      ;;
  esac
  shift
done

PATH=${PATH}:/usr/local/bin
export PATH

detect_endpoint
update_endpoint

kubectl delete pods --all -A --force --grace-period=0

sleep 10

apply_changes

echo "https://$(cat /etc/spinnaker/.hal/public_endpoint)"
echo "username: 'admin'"
echo "password: '$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)'"
