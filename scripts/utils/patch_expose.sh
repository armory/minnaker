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

function disable_cors() {
  local YAML_FILE=$BASE_DIR/expose/patch-urls.yml
  info 'Set CORS pattern to ^.*$'
  yq e -i '.spec.spinnakerConfig.config.security.apiSecurity.corsAccessPattern="^.*$"' $YAML_FILE
}

function enable_cors() {
  local YAML_FILE=$BASE_DIR/expose/patch-urls.yml
  info 'Set CORS pattern to '$1
  yq e -i '.spec.spinnakerConfig.config.security.apiSecurity.corsAccessPattern="'$1'"' $YAML_FILE
}

function expose_service_via_loadbalancer() {
  local YAML_FILE=$BASE_DIR/expose/patch-lb-static-ip.yml
  local SERVICE=$1

  local KUSTOMIZE_LB_SPEC='{"spec":{"type":"LoadBalancer","loadBalancerIP":"1.2.3.4","ports":[{"name":"http","port":8083,"targetPort":8083}]}}'

  info 'Expose service '$SERVICE
  yq e '.spec.kustomize.'"$SERVICE"'.service.patches|=['$KUSTOMIZE_LB_SPEC']' $YAML_FILE
}