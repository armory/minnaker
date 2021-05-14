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

function disable_security() {
  local YAML_FILE=$BASE_DIR/security/patch-basic-auth.yml
  info 'Disable gate security'
  yq e -i '.spec.spinnakerConfig.profiles.gate.security.basicform.enabled=false' $YAML_FILE
  yq e -i 'del(.spec.spinnakerConfig.profiles.gate.spring.security)' $YAML_FILE
  info 'File '$YAML_FILE' was patched'
}

function enable_security() {
    local YAML_FILE=$BASE_DIR/security/patch-basic-auth.yml
    info 'Enable gate security'
    yq e -i '.spec.spinnakerConfig.profiles.gate.security.basicform.enabled=true' $YAML_FILE
    yq e -i --prettyPrint '.spec.spinnakerConfig.profiles.gate.spring={"security": {"user": {"name":"admin", "password":"123"}}}' $YAML_FILE
    info 'File '$YAML_FILE' was patched'
}
