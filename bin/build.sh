#!/bin/bash
set -x

mkdir -p build
BASENAME=$(basename $(pwd))
cd .. && tar -czvf ${BASENAME}/build/minnaker.tgz ${BASENAME}/templates/ ${BASENAME}/scripts/