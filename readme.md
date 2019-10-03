This is a work in progress to do the following:

* Given a single Linux machine (currently tested with Ubuntu 18.04
* Install k3s
  * Traefik turned off
* Install minio in k3s
  * Use a local volume
* Set up Halyard in a Docker container
* Install Spinnaker

By default, this will install Spinnaker and configure it to listen on port 80 and 8084 (for the UI and API).

If you have the ability to set up DNS pointing to your instance, you can switch to two DNS names (such as http://spinnaker.domain.com and http://gate.domain.com) using the instructions in [Switch to DNS](switch_to_dns).

