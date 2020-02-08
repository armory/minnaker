#!/bin/bash

# This is a wrapper for scripts that download all.sh and run them directly
curl -LO https://github.com/armory/minnaker/releases/download/0.0.7/minnaker.tgz
tar -xzvf minnaker.tgz
./minnaker/scripts/install.sh $@
