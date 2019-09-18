# Spinnaker in under 5 minutes

## Background
* Given a single Linux machine (_currently tested with Ubuntu 18.04 and Debian 10)_
* [Install k3s](http://rancher.com)
  * Traefik turned off
* Install minio in k3s
  * Use a local volume
* Set up **Halyard** in a Docker container
* Install **Spinnaker**
* Configure development environment

## Prequisites
- Linux distribution running in a VM or bare metal
  - 2 vCPUs
  - 8Gb of RAM
  - 10Gb of HDD
  - NAT or Bridged networking with access to the internet
- Install `curl` and `git`
---
**Debian**

`sudo apt-get install curl git`

**Fedora/CentOS**

`sudo yum install curl git`

---

## Installation
- Login to your VM or bare metal box
- Clone the mini-spinnaker repository

`git clone https://github.com/armory/mini-spinnaker`

- Change the working directory to _mini-spinnaker/scripts_

`cd mini-spinnaker/scripts`

- Make the install script executable

`chmod 775 all.sh`

- Execute the install script

`./all.sh`

- Choose if you want Armory Spinnaker or OSS Spinnaker
- Installation will continue and take about 5 minutes to complete

## Accessing Spinnaker
- Determine you IP_ADDR

`hostname -I`

- Open your browser to the above IP_ADDR
- Get the Spinnaker password (you may need to ssh into your machine)

`cat /etc/spinnaker/.hal/.secret/spinnaker_password`

- User credentials
  - User: **admin**
  - Password: _paste from above_

## Changing Your Spinnaker Configuration
- SSH into the machine where you have installed Spinnaker
- Access the Halyard pod

` export HAL_POD=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)`

` kubectl -n spinnaker exec -it ${HAL_POD} bash` 

- Run Halyard configuration commands like this example

`hal config version`

- Type `exit` to leave the pod
- All of the Halyard configuration files are stored in `/etc/spinnaker/.hal`






