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

# Not (currently) designed for OSX

# This is used to 'reset' a Minnaker instance.  It regenerates the Minio and Gate passwords
# Also, it will do the following with the public endpoint:
# # If a new public endpoint is provided (with the flag -P), then the new endpoint will be used
# # Otherwise, if the previous public endpoint was provided was a flag, that endpoint will be used
# # Otherwise, the public endpoint will be re-detected

# set -x
set -e

##### Functions
print_help () {
  set +x
  echo "Usage: refresh_endpoint.sh"
  echo "               [-P|--public-endpoint <PUBLIC_IP_OR_DNS_ADDRESS>]  : Specify public IP (or DNS name) for instance (rather than autodetection)"
  echo "               [-B|--base-dir <BASE_DIRECTORY>]                   : Specify root directory to use for manifests"
  set -x
}

apply_changes () {
  info "Executing ${BASE_DIR}/deploy.sh"
  cd "${BASE_DIR}"
  ./deploy.sh
}

PUBLIC_ENDPOINT=""
PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" >/dev/null 2>&1 && pwd )
BASE_DIR=${BASE_DIR:=$PROJECT_DIR/spinsvc}
OUT="$PROJECT_DIR/minnaker.log"

. "${PROJECT_DIR}/scripts/functions.sh"

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

info "Refreshing Endpoint"

detect_endpoint force_refresh
update_endpoint
restart_k3s
apply_changes
spin_endpoint