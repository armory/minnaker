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

set -e

# Linux only

PROJECT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../" >/dev/null 2>&1 && pwd )
BASE_DIR=$PROJECT_DIR/spinsvc

OUT=/dev/null
### Load Helper Functions
. "${PROJECT_DIR}/scripts/functions.sh"

## Import patch functions
. ./patch_security.sh
. ./patch_expose.sh

case "$1" in
  security)
    case "$2" in
      enable)
        enable_security
      ;;
      disable)
        disable_security
      ;;
      *)
        warn 'enable or disable?'
        exit 1
      ;;
    esac
  ;;
  cors)
    case "$2" in
      disable)
        disable_cors
      ;;
      enable)
        # Not sure right now how to get an actual IP of the cluster
        enable_cors '192.168.64.4'
      ;;
    *)
      warn 'enable or disable?'
      exit 1
    ;;
    esac
  ;;
  lb)
    case "$2" in
      expose)
        expose_service_via_loadbalancer $3
      ;;
      *)
        warn 'expose [service_name{, service_name}] or expose all'
        exit 1
      ;;
    esac
  ;;
  *)
    warn "Please specify certain functionality to patch:\n- security\n- cors"
    exit 1
esac

info 'Apply changes to kubernetes'
$BASE_DIR/deploy.sh