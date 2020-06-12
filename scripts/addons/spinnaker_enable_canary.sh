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

set -x
set -e

######
hal config canary enable
hal config canary prometheus enable
hal config canary prometheus account add prometheus --base-url http://prometheus.default:9090/prometheus

hal config canary aws enable
# For some reason, Kayenta doesn't like using the same bucket as Front50, so we're setting up a different bucket
# This will result in s3://kayenta/kayenta
# TODO: Detect existing account
echo "MINIO_PASSWORD" | hal config canary aws account add minio --bucket kayenta --root-folder kayenta --endpoint http://minio.spinnaker:9000 --access-key-id minio --secret-access-key
hal config canary aws edit --s3-enabled=true

hal config canary edit --default-metrics-store prometheus
hal config canary edit --default-metrics-account prometheus
hal config canary edit --default-storage-account minio

# TODO: Detect existence of this
# Extra blank lines are intentional
tee -a /etc/spinnaker/.hal/default/profiles/gate-local.yml <<-'EOF'

services:
  kayenta:
    canaryConfigStore: true

EOF

hal deploy apply