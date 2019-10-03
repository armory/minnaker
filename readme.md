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

Notes:
* If you shut down and restart the instance and it gets different IP addresses, you'll have to change some stuff:
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
