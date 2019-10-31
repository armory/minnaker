# Adding additional deployment targets (Kubernetes clusters) to Spinnaker

Minnaker installs a local distribution of Kubernetes (K3s) on your VM, which can be deployed to, but once Spinnaker is up and running, you can configure Spinnaker to be able to deploy to additional Kubernetes clusters.  Each of these is added as a Clouddriver **account**, which is information about a Kubernetes cluster (API server URL, certificate, credentials) that Spinnaker uses to interact with that Kubernetes cluster.

In order to do this, you basically need to generate a `kubeconfig` file that has credentials for your target Kubernetes cluster, and then give that to Spinnaker.


## Overview

We're going to use the `spinnaker-tools` tool (which is a kubectl wrapper) to do the following:

In the target Kubernetes cluster:
* Create a `ServiceAccount` in the `kube-system` namespace (`spinnaker-service-account`)
* Create a `ClusterRoleBinding` to grant the service account access to the Kubernetes `cluster-admin` role (`kube-system-spinnaker-service-account-admin`)

The tool will also do this:
* Create a `kubeconfig` file with the token for the generated service account

Then we will take the generated kubeconfig, copy it to Minnaker, and configure Minnaker to use the kubeconfig to be able to deploy to your Kubernetes cluster.

## Prerequisities

This process should be run from your local workstation, *not from the Minnaker VM*.  You must have access to the Kubernetes cluster you would like to deploy to, and you need cluster admin permissions on the Kubernetes cluster.

You should be able to run the following (again, from your local workstation, not the Minnaker VM).

```bash
kubectl get ns
```

You should also be able to copy files from your local workstation to the Minnaker VM.

## Using `spinnaker-tools`

On your local workstation (where you currently have access to Kubernetes), download the spinnaker-tools binary:

If you're on a Mac:

```bash
curl -L https://github.com/armory/spinnaker-tools/releases/download/0.0.7/spinnaker-tools-darwin -o spinnaker-tools
chmod +x spinnaker-tools
```

If you're on Linux:

```bash
curl -L https://github.com/armory/spinnaker-tools/releases/download/0.0.7/spinnaker-tools-linux -o spinnaker-tools
chmod +x spinnaker-tools
```

Then, run it:

```bash
./spinnaker-tools create-service-account
```

This will prompt for the following:
* Select the Kubernetes cluster to deploy to (this helps if you have multiple Kubernetes clusters configured in your local kubeconfig)
* Select the namespace (choose the `kube-system` namespace, or select some other namespace or select the option to create a new namespace).  This is the namespace that the Kubernetes ServiceAccount will be created in.
* Enter a name for the service account.  You can use the default `spinnaker-service-account`, or enter a new (unique) name.
* Enter a name for the output file.  You can use the default `kubeconfig-sa`, or you can enter a unique name.  You should use something that identifies the Kubernetes cluster you are deploying to (for example, if you are setting up Spinnaker to deploy to your us-west-2 dev cluster, then you could do something like `kubeconfig-us-west-2-dev`)

This will create the service account (and namespace, if applicable), and the ClusterRoleBinding, then create the kubeconfig file with the specified name.

Copy this file from your local workstation to your Minnaker VM.  You can use scp or some other copy mechanism.

## Add the kubeconfig to Spinnaker's Halyard Configuration

On the Minnaker VM, move or copy the file to `/etc/spinnaker/.hal/.secret` (make sure you are creating a new file, not overwriting an existing one).

Then, run this command:

```bash
hal config provider kubernetes account add us-west-2-dev \
  --provider-version v2 \
  --kubeconfig-file /home/spinnaker/.hal/.secret/kubeconfig-us-west-2-dev \
  --only-spinnaker-managed true
```

Note two things:
* Replace us-west-2-dev with something that identifies your Kubernetes cluster
* Update the `--kubeconfig-file` path with the correct filename.  Note that the path will be `/home/spinnaker/...` **not** `/etc/spinnaker/...` - this is because this command will be run inside the Halyard container, which has local volumes mounted into it.

## Apply your changes

Run this command to apply your changes to Spinnaker:

```bash
hal deploy apply --wait-for-completion
```

## Use the new cluster

Log into the Spinnaker UI (you should first do this in incognito, or do a hard refresh of your browser, as Spinnaker very aggressively caches information in your browser).  

When you go to set up a Kubernetes deployment stage, you should see your new Kubernetes deployment target in the `Account` dropdown.

## Additional options / Alternate configurations

All Halyard / Spinnaker really needs is a way to communicate with your Kubernetes cluster with a Kubeconfig.  You can customize this configuration in a number of different ways:

### Automate this process
The `spinnaker-tools` binary supports command-line flags.  You can use `-h` to see the options (as in `./spinnaker-tools create-service-account -h`), and could run the above command as something like this:

```bash
./spinnaker-tools create-service-account \
  --kubeconfig ~/.kube/config \
  --context my-kubernetes-context \
  --namespace kube-system \
  --service-account-name minnaker-service-account \
  --output kubeconfig-my-kubernetes-cluster
```

Spinnaker tools also supports using existing ServiceAccounts using the `./spinnaker-tools create-kubeconfig` command).  Setting up permissions here is left as an exercise to the reader.

### Set up per-namespace access

One option you can do, as you're setting up Spinnaker with RBAC, is set up different Clouddriver `account`s for different namespaces.  For example, you could set up something like this:

Prod Cluster
* `frontend` namespace
* `backend` namespace

Dev Cluster
* `frontend` namespace
* `backend` namespace

To set up the service account and user, you can use the --target-namespaces flag for `./spinnaker-tools create-service-account`.  For example:

```bash
./spinnaker-tools create-service-account \
  --kubeconfig ~/.kube/config \
  --context prod-cluster \
  --namespace kube-system \
  --service-account-name minnaker-prod-frontend-access \
  --output kubeconfig-prod-frontend \
  --target-namespaces frontend
```

(Repeat the above four times, with different parameters)

Then set up a different Kubeconfig for each cluster/namespace (four total kubeconfigs), and add four accounts using `hal config provider`, using the `--namespaces` flag:

```bash
hal config provider kubernetes account add prod-frontend \
  --provider-version v2 \
  --kubeconfig-file /home/spinnaker/.hal/.secret/kubeconfig-prod-frontend \
  --only-spinnaker-managed true \
  --namespaces frontend
```

(Again, repeat four times)

### Use IAM roles for AWS EKS

AWS EKS supports the use of AWS IAM roles to access your Kubernetes cluster.  To do this, you can do the following:

* Attach an IAM role to the VM where Minnaker is running
* Add that role to the `aws-auth` configmap in your target EKS cluster (this lives in the `kube-system` namespace).
* Generate a kubeconfig that uses `aws-iam-authenticator` to generate tokens (look at your existing `~/.kube/config` for an example of this)
* Use this kubeconfig as opposed to the one generated above.

This is left as an exercise to the reader (or reach out to us for help and we can get you up and running!)
