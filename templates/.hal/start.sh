#!/bin/bash
# Determine port detection method
if [[ $(ss -h &> /dev/null; echo $?) -eq 0 ]];
then
  ns_cmd=ss
else
  ns_cmd=netstat
fi

# Wait for Spinnaker to start
while [[ $(${ns_cmd} -plnt | grep 8064 | wc -l) -lt 1 ]];
do
  echo 'Waiting for Halyard daemon to start';
  sleep 2;
done

VERSION=$(hal version latest -q)

hal config version edit --version ${VERSION}
sleep 5

echo ""
echo "Installing Spinnaker - this may take a while (up to 10 minutes) on slower machines"
echo ""

hal deploy apply --wait-for-completion

echo "https://$(cat /home/spinnaker/.hal/public_endpoint)"
echo "username: 'admin'"
echo "password: '$(cat /home/spinnaker/.hal/.secret/spinnaker_password)'"