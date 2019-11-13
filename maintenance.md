# Maintenance

## Update URL

If the public IP address of your Mini-Spinnaker has changed, or if you want to change the access URL (for example, to switch from IP to DNS name or from DNS name to IP), then do this:

```bash
# This can be an IP address.  For example:
# ENDPOINT=https://35.35.35.35
# or a DNS name.  For example:
# ENDPOINT=https://ec2-35-35-35-35.us-west-2.compute.amazonaws.com
# Either way, don't use a trailing slash
# You can use either http or https - if https, you'll end up with the self-signed Traefik certificate
ENDPOINT=https://<your-new-ip-or-hostname>

# This file is only used during bootstrapping, and will only cause confusion
rm /etc/spinnaker/.hal/public_ip

echo ${ENDPOINT} > /etc/spinnaker/.hal/endpoint

hal config security ui edit --override-base-url ${ENDPOINT}
hal config security api edit --override-base-url ${ENDPOINT}/api/v1

hal deploy apply
```

## Change Static Password

```bash
# Doesn't support '|' cause of the sed; todo fix.
PASSWORD=my-new-password
echo ${PASSWORD} > /etc/spinnaker/.hal/.secret/spinnaker_password
sed -i "s|password:.*|password: ${PASSWORD}|g" /etc/spinnaker/.hal/default/profiles/gate-local.yml
hal deploy apply --service-names gate --wait-for-completion
```
