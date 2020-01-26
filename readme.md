# Spinnaker All-In-One (Minnaker) Quick Start

**Previously known as Mini-Spinnaker**

Minnaker is currently intended for POCs and trying out Spinnaker.

## Background

Minnaker performs the following actions when run on a single Linux instance:

* Installs [k3s](http://rancher.com) with Traefik turned off.
* Installs minio in k3s with a local volume.
* Sets up **Halyard** in a Docker container (running in Kubernetes).
* Installs **Spinnaker** using Halyard.
* Minnaker uses local authentication. The username is `admin` and the password is randomly generated when you install Minnaker. Find more details about getting the password in [Accessing Spinnaker](#accessing-spinnaker).
* [Optionally] Configures development environment.

## Requirements

To use Minnaker, make sure your Linux instance meets the following requirements:

* Linux distribution running in a VM or bare metal
    * Ubuntu 18.04 or Debian 10 (VM or bare metal)
    * 2 vCPUs (recommend 4)
    * 8GiB of RAM (recommend 16)
    * 30GiB of HDD (recommend 40+)
    * NAT or Bridged networking with access to the internet
    * Install `curl` and `tar` (if they're not already installed):
        * `sudo apt-get install curl tar`
    * Port `443` on your VM needs to be accessible from your workstation / browser. By default, Minnaker installs Spinnaker and configures it to listen on port `443`, using paths `/` and `/api/v1`(for the UI and API).
* OSX
    * Docker Desktop local Kubernetes cluster enabled
    * At least 6 GiB of memory allocated to Docker Desktop


## Changelog 

* As of 1/14/2020, Minnaker only uses a kubernetes service account for its local deployment, and supports installation on Docker for Desktop.  It no longer needs a private IP link, only the public endpoint (only need -P, not -p).
* As of 11/11/2019, Minnaker uses port 443 (instead of 80) and Traefik's default self-signed certificate.
* If you installed Minnaker prior to November 2019, you can switch to the new path mechanism using [Switch to Paths](switch_to_paths.md).
* As of 10/18/2019, Minnaker no longer uses port 8084.

---

## Installation

1. Login (SSH) to your VM or bare metal box.
2. Download the minnaker tarball:

    ```bash
    curl -LO https://github.com/armory/minnaker/releases/download/0.0.1/minnaker.tgz
    ```

3. Untar the tarball (will create a `./minnaker` directory in your current working directory):

    ```bash
    tar -xzvf minnaker.tgz
    ```

4. Change into the directory:

    ```bash
    cd minnaker
    ```

5. Execute the install script. Note the following options before running the script:
     * Add the `-o` flag if you want to install open source Spinnaker.
     * By default, the script installs Armory Spinnaker and uses your public IP address (determined by `curl`ing `ifconfig.co`) as the endpoint for Spinnaker.
     * For bare metal or a local VM, specify the IP address for your server with `-P` flag. `-P` is the 'Public Endpoint' and must be an address or DNS name you will use to access Spinnaker (an IP address reachable by your end users).

    ```bash
    ./scripts/install.sh
    ```

    If you would like to install Open Source Spinnaker, use the `-o` flag.

    For example, the following command installs OSS Spinnaker on a VM with the IP address of `192.168.10.1`:

    ```bash
    export PRIVATE_ENDPOINT=192.168.10.1
    ./scripts/install.sh -o -P $PRIVATE_ENDPOINT
    ```

    Installation can take between 5-10 minutes to complete depending on VM size.

6. Once Minnaker is up and running, you can make changes to its configuration using `hal`.  For example, to change the version of Spinnaker that is installed, you can use this:

    ```bash
    hal config version edit --version 2.17.4

    hal deploy apply
    ```

    *By default, Minnaker will install the latest GA version of Spinnaker available.*

## Accessing Spinnaker

1.  Determine the public endpoint for Spinnaker

    ```bash
    grep override /etc/spinnaker/.hal/config
    ```

    Use the first URL.

2. Get the Spinnaker password. On the Linux host, run the following command:

    ```bash
    cat /etc/spinnaker/.hal/.secret/spinnaker_password
    ```

3. In your browser, navigate to the IP_ADDR (https://IP/) for Spinnaker from step 1. This is Deck, the Spinnaker UI.
     
     If you installed Minnaker on a local VM, you must access it from your local machine. If you deployed Minnaker in the cloud, such as an EC2 instance, you can access Spinnaker from any machine that has access to that 'Public IP'.

4. Log in to Deck with the following credentials:
   
    Username: `admin`

    Password: <Password from step 2>   

## Changing Your Spinnaker Configuration

1. SSH into the machine where you have installed Spinnaker
2. Access the Halyard pod:

    ```bash
    export HAL_POD=$(kubectl -n spinnaker get pod -l app=halyard -oname | cut -d'/' -f 2)

    kubectl -n spinnaker exec -it ${HAL_POD} bash
    ```

3. Run Halyard configuration commands. For example, the following command allows you to configure and view the current deployment of Spinnaker’s version.

    ```bash
    hal config version
    ```
    All Halyard configuration files are stored in `/etc/spinnaker/.hal`

    For more information about Armory's Halyard, see [Armory Halyard commands](https://docs.armory.io/spinnaker/armory_halyard/).

    For more information about open source Halyard, see [Halyard commands](https://www.spinnaker.io/reference/halyard/commands/).    
  
4. When finished, use the `exit` command to leave the pod.


## Details

* If you shut down and restart the instance and it gets different IP addresses, you'll have to update Spinnaker with the new IP address(es):

  * If the public IP address has changed:
    * Update `/etc/spinnaker/.hal/public_endpoint` with the new public IP address
    * Update `/etc/spinnaker/.hal/config` Update with the new public IP addresses (Look for both `overrideBaseUrl` fields) (if you haven't switched to DNS)
    * `/etc/spinnaker/.hal/config-seed` Update with the new public IP addresses (Look for both `overrideBaseUrl` fields) (if you haven't switched to DNS)
  * Run `hal deploy apply`

* Certificate support isn't yet documented.  There are several ways to achieve this:
  * Using actual cert files: create certs that Traefik can use in the ingress definition(s)
  * Using ACM or equivalent: put a certificate in front of the instance and change the overrides
  * Either way, you *must* use certificates that your browser will trust that match your DNS name (your browser may not prompt to trust the untrusted API certificate)

* If you need to get the password again, you can see the generated password in `/etc/spinnaker/.hal/.secret/spinnaker_password`:

  ```bash
  cat /etc/spinnaker/.hal/.secret/spinnaker_password
  ```

## Uninstall Minnaker for OSX
* Delete the `spinnaker` namespace: `kubectl --context docker-desktop delete ns spinnaker`
* (Optionally) delete the `ingress-nginx` namespace: `kubectl --context docker-desktop delete ns ingress-nginx`
* (Optionally) delete the local resources (including all pipeline defs): `rm -rf ~/minnaker`
