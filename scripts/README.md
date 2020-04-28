# Scripts

This directory holds the scripts that make up the core of Minnaker.

We use `yml` instead of `yaml` for consistency (all service-settings and profiles require `yml`)

## TODOs

* Linux: detect existence of Kubernetes
* Move metrics server manifests (and see if we need it) - also detect existence
* Figure out nginx vs. traefik (nginx for m4m, traefik for ubuntu?, or use helm?)
* Exclude spinnaker namespace - not doing this
* Update 'public_ip'/'PUBLIC_IP' to 'public/endpoint/PUBLIC_ENDPOINT'
* Fix localhost public ip for m4m
* Remove password for minio

## WIP
* Canned apps and pipelines*OOB application(s)
* Refactor all hydrates into a function: copy_and_hydrate