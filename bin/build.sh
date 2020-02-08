#!/bin/bash
set -x

mkdir -p build/minnaker
cp -rpv templates scripts build/minnaker
cd build && tar -czvf minnaker.tgz minnaker