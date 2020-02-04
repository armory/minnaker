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
  echo "Usage: regenerate_password.sh"
  set -x
}

generate_passwords () {
  # echo "Generating Minio password (${BASE_DIR}/.hal/.secret/minio_password):"
  # openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/minio_password

  echo "Generating Spinnaker password (${BASE_DIR}/.hal/.secret/spinnaker_password):"
  openssl rand -base64 36 | tee ${BASE_DIR}/.hal/.secret/spinnaker_password
}

# update_minio_password () {
#   MINIO_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/minio_password)
#   yq w -i ${BASE_DIR}/manifests/minio.yml spec.template.spec.containers[0].env[1].value ${MINIO_PASSWORD}
#   yq w -i ${BASE_DIR}/.hal/config deploymentConfigurations[0].persistentStorage.s3.secretAccessKey ${MINIO_PASSWORD}
# }

update_spinnaker_password () {
  SPINNAKER_PASSWORD=$(cat ${BASE_DIR}/.hal/.secret/spinnaker_password)
  yq w -i ${BASE_DIR}/.hal/default/profiles/gate-local.yml security.user.password ${SPINNAKER_PASSWORD}
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

  kubectl -n spinnaker exec -i halyard-0 -- hal deploy apply --wait-for-completion
}

# PUBLIC_ENDPOINT=""
BASE_DIR=/etc/spinnaker

while [ "$#" -gt 0 ]; do
  case "$1" in
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

generate_passwords

# update_minio_password
touch ${BASE_DIR}/.hal/password_generated
update_spinnaker_password

apply_changes

echo "https://$(cat /etc/spinnaker/.hal/public_endpoint)"
echo "username: 'admin'"
echo "password: '$(cat /etc/spinnaker/.hal/.secret/spinnaker_password)'"
