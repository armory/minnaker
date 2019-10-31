# Spinnaker All-In-One (Minnaker) Quick Start

**Previously known as Mini-Spinnaker**

This is currently intended for POCs and trying out Spinnaker.

## Background

* Given a single Linux machine (currently tested with Ubuntu 18.04 and Debian 10)
* Install [k3s](http://rancher.com)
  * Traefik turned off
* Install minio in k3s
  * Use a local volume
* Set up **Halyard** in a Docker container (running in Kubernetes)
* Install **Spinnaker** using Halyard
* [Optionally] Configure development environment

## Prequisites

* Linux distribution running in a VM or bare metal
  * 2 vCPUs (recommend 4)
  * 8Gb of RAM (recommend 16)
  * 30GB of HDD (recommend 40+)
  * NAT or Bridged networking with access to the internet

* Install `curl` and `git`:
  * **Debian**
    * `sudo apt-get install curl git`
  * **Fedora/CentOS**
    * `sudo yum install curl git`

---

## Installation

* Login (SSH) to your VM or bare metal box
* Clone the minnaker repository

  ```bash
  git clone https://github.com/armory/minnaker
  ```

* Change the working directory to _minnaker/scripts_

  ```bash
  cd minnaker/scripts
  ```

* Make the install script executable

  ```bash
  chmod 775 all.sh
  ```

* Execute the install script (add the `-o` flag if you want OSS Spinnaker)

  This will, by default, install Armory Spinnaker and use your public IP address (determined by `curl`ing `ifconfig.co`) as the endpoint for Spinnaker.  If you are installing this on a baremetal or local VM, you should indicate the IP address for your server with the `-p` and `-P` flags (`-p` is the 'Private IP', and must be an IP address that exists on an interface on the machine; `-P` is the 'Public IP' and must be an address or DNS name you will use to access Spinnaker).

  ```bash
  ./all.sh
  ```

  For example, to install OSS Spinnaker on a VM with the IP address of 192.168.10.1, you could do something like this:

  ```bash
  ./all.sh -o -P 192.168.10.1 -p 192.168.10.1
  ```

* Installation will continue and take about 5-10 minutes to complete, depending on VM size

## Accessing Spinnaker

* Determine you IP_ADDR

  ```bash
  hostname -I
  ```

* Open your browser to the above IP_ADDR (http://IP/)
* Get the Spinnaker password (you may need to ssh into your machine)

  ```bash
  cat /etc/spinnaker/.hal/.secret/spinnaker_password
  ```

* User credentials
  * User: **admin**
  * Password: _paste from above_

* Port 80 on your VM need to be accessible from your workstation / browser
* _As of 10/18/2019, we no longer need port 8084_

## Changing Your Spinnaker Configuration

* SSH into the machine where you have installed Spinnaker
* Access the Halyard pod

  ```bash
  export HAL_POD=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)`
  kubectl -n spinnaker exec -it ${HAL_POD} bash`
  ```

* Run Halyard configuration commands like this example

  ```bash
  hal config version
  ```

* Type `exit` to leave the pod
* All of the Halyard configuration files are stored in `/etc/spinnaker/.hal`

## Details

By default, this will install Spinnaker and configure it to listen on port 80, using paths `/` and `/api/v1`(for the UI and API).

You can switch to the new path mechanism using [Switch to Paths](switch_to_paths).

Notes:

* If you shut down and restart the instance and it gets different IP addresses, you'll have to update Spinnaker with the new IP address(es):

  * If the public IP address has changed:
    * Update /etc/spinnaker/.hal/public_ip with the new public IP address
    * Update /etc/spinnaker/.hal/config and /etc/spinnaker/.hal/config-seed with the new public IP addresses (each one should have two `overrideBaseUrl` fields) (if you haven't switch to DNS)
  * If the private IP address has changed:
    * Update /etc/spinnaker/.hal/private_ip with the new private IP address
    * Update the kubeconfigs at /etc/spinnaker/.kube/config and /etc/spinnaker/.hal/.secret/kubeconfig-spinnaker-sa with the new private IP address (in the `.clusters.cluster.server` field)
  * Run `hal deploy apply`

* Certificate support isn't yet documented.  Many ways to achieve this:
  * Using actual cert files, create certs that Traefik can use in the ingress definition(s)
  * Using ACM or equivalent, put a certificate in front of the instance and change the overrides
  * Either way, you *must* use certificates that your browser will trust that match your DNS name (your browser may not prompt to trust the untrustted API certificate)

* If you need to get the password again, you can see the generated password at `/etc/spinnaker/.hal/.secret/spinnaker_password`:

  ```bash
  cat /etc/spinnaker/.hal/.secret/spinnaker_password
  ```
