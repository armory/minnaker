# Spinnaker All-In-One (Minnaker) Quick Start

Minnaker is a simple way to install Spinnaker inside a VM.

## Background

Minnaker performs the following actions when run on a single Linux instance:

* Installs [k3s](https://k3s.io/) with Traefik.
* Installs minio in k3s with a local volume.
* Installs mysql in k3s.
* Installs redis in k3s.
* Installs **[Spinnaker Operator](https://github.com/armory/spinnaker-operator)**.
* Clones the "minnaker" branch in https://github.com/armory/spinnaker-kustomize-patches for the purposes of configuring Spinnaker.
* Installs and configures **[Spinnaker](https://github.com/spinnaker)** or **[Armory](https://armory.io)** using the **Spinnaker Operator**.
* Exposes Spinnaker using an Ingress.  NOTE: If you're using an AWS EC2 instance, make sure you add port 443 to the security group.
* Minnaker uses local authentication. The username is `admin` and the password is randomly generated when you install Minnaker. Find more details about getting the password in [Accessing Spinnaker](#accessing-spinnaker).
* For the full list of customizations and configurations - please check out the [kustomization-minnaker.yml] (https://github.com/armory/spinnaker-kustomize-patches/blob/minnaker/recipes/kustomization-minnaker.yml) file.

## Requirements

To use Minnaker, make sure your Linux instance meets the following requirements:

* Linux distribution running in a VM or bare metal
    * Ubuntu 18.04 or Debian 10 (VM or bare metal)
    * 2 vCPUs (recommend 4)
    * 8GiB of RAM (recommend 16)
    * 30GiB of HDD (recommend 40+)
    * NAT or Bridged networking with access to the internet
    * Install `curl`, `git`, and `tar` (if they're not already installed):
        * `sudo apt-get install curl git tar`
    * Port `443` on your VM needs to be accessible from your workstation / browser. By default, Minnaker installs Spinnaker and configures it to listen on port `443`, using paths `/` and `/api/v1`(for the UI and API).
* OSX
    * Docker Desktop local Kubernetes cluster enabled
    * At least 6 GiB of memory allocated to Docker Desktop

* On Ubuntu, the Minnaker installer will install K3s for you (a minimal installation of Kubernetes), so you do not have to pre-install Docker or Kubernetes.

## Changelog

* 2/XX/2021 - Major update - install.sh has been replaced to use the spinnaker operator as the default installation method.  Todo: Many of the convience scripts will also need to be updated to use the operator as well.  If you would still like to use Halyard - please reference [Release 0.0.23](https://github.com/armory/minnaker/releases/tag/0.0.22)
  * operator_install.sh replaces install.sh
  * removing operator_install.sh
  * ToDo: Clean up all other scripts to remove dependency on halyard.
  * see notes below on currently supported scripts

---

## Installation

1. Login (SSH) to your VM or bare metal box.
2. Download the minnaker tarball and untar:

    ```bash
    curl -L https://github.com/armory/minnaker/archive/v0.1.3.tar.gz | tar -zxv
    ```

3. Change into the directory:

    ```bash
    cd minnaker-0.1.*
    ```

4. Execute the install script. Note the following options before running the script:
     * Add the `-o` flag if you want to install open source Spinnaker.
     * By default, the script installs Armory Spinnaker and uses your public IP address (determined by `curl`ing `ifconfig.co`) as the endpoint for Spinnaker.
     * For bare metal or a local VM, specify the IP address for your server with `-P` flag. `-P` is the 'Public Endpoint' and must be an address or DNS name you will use to access Spinnaker (an IP address reachable by your end users).

    ```bash
    ./scripts/install.sh
    ```
    
    For example, the following command installs OSS Spinnaker on a VM with the IP address of `192.168.10.1`:

    ```bash
    export PRIVATE_IP=192.168.10.1
    ./scripts/install.sh -o -P $PRIVATE_IP
    ```

    Installation can take between 5-10 minutes to complete depending on VM size.

5. Once Minnaker is up and running, you can make changes to its configuration using `kustomize` and the `spinnaker-operator` under the folder `~/minnaker-1.0.1/spinsvc`.  For example, to change the version of Spinnaker that is installed, you can do this:

  * Using your favorite editor, edit the file: `~/minnaker-1.0.1/spinsvc/core_config/patch-version.yml`
  * Update line 8 to the version you desire. e.g. `version: 2.24.0`
  * Then either run `cd ~/minnaker-1.0.1/spinsvc && ./deploy.sh` or `kubectl apply -k ~/minnaker-1.0.1/spinsvc`
  * To find the latest versions available:
      * [Spinnaker](https://spinnaker.io/community/releases/versions/#latest-stable)
      * [Armory](https://docs.armory.io/docs/release-notes/rn-armory-spinnaker/)
  * *By default, Minnaker will install the latest GA version of Spinnaker or Armory available.*

## Accessing Spinnaker

1.  A helper script called `spin_endpoint` was created during the installation process that prints out the URL associated with your spinnaker instance as well as the credentials (as necessary).

    ```bash
    spin_endpoint
    ```

    outputs: 
    ```bash
    https://192.168.64.3
    username: 'admin'
    password: 'xxxxx'
    ```
    
2. In your browser, navigate to the address (https://192.168.64.3/) for Spinnaker from step 1. This is Deck, the Spinnaker UI.

     If you installed Minnaker on a local VM, you must access it from your local machine. If you deployed Minnaker in the cloud, such as an EC2 instance, you can access Spinnaker from any machine that has access to that 'Public IP'.

3. Log in to Deck with the following credentials:

    Username: `admin`

    Password: <Password from step 1>   

## Changing Your Spinnaker Configuration

1. SSH into the machine where you have installed Spinnaker
2. Modify the contents of `~/spinnaker/spinsvc/kustomization.yml` and the associated patch files. 

** PRO TIP: Use [VS Code - Remote SSH extension](https://code.visualstudio.com/docs/remote/ssh) to interact with your minnaker instance, and manage and edit multiple files **

    See [Armory's Spinnaker Operator] (https://docs.armory.io/docs/installation/operator/).
    
    By default, the install script clones [Armory's Spinnaker Kustomize Patches repo (branch: minnaker)](https://github.com/armory/spinnaker-kustomize-patches/tree/minnaker). This branch has been pre-configured with many features to make learning Spinnaker easy. 

    [Armory Operator Reference](https://docs.armory.io/docs/installation/operator-reference/)

4. When finished save your changes, and run `deploy.sh` located under `~/spinnaker/spinsvc`.

## Next Steps

After you finish your installation of Minnaker, go through our [AWS QuickStart](https://docs.armory.io/spinnaker/Armory-Spinnaker-Quickstart-1/) to learn how to deploy applications to AWS with Spinnaker.

Alternatively, take a look at the available Minnaker [guides](/guides/).

To learn more about the Spinnaker Operator check out the docs here: https://docs.armory.io/docs/installation/operator/

Also check out the [`spinnaker-kustomize-patches`](https://github.com/armory/spinnaker-kustomize-patches#kustomize-patches-for-armory) repo

## Details

* If you shut down and restart the instance and it gets different IP addresses, you'll have to update Spinnaker with the new IP address(es):
  * Run `refresh_endpoint.sh` and this will try to detect your new IP address and update the spinnaker configuration to your new IP address.

* Certificate support isn't yet documented.  There are several ways to achieve this:
  * Using actual cert files: create certs that Traefik can use in the ingress definition(s)
  * Using ACM or equivalent: put a certificate in front of the instance and change the overrides
  * Either way, you *must* use certificates that your browser will trust that match your DNS name (your browser may not prompt to trust the untrusted API certificate)

* If you need to get the password again, you can execute the command `spin_endpoint` (this was added by the install script under `/usr/local/bin`)

## Troubleshooting

Under the hood, Minnaker just wraps Spinnaker Operator, so it still runs all the components of Spinnaker as Kubernetes pods in the `spinnaker` namespace.  You can use standard Kubernetes troubleshooting steps to troubleshoot Spinnaker components.

For example, to see all the components of Minnaker:

```bash
$ kubectl -n spinnaker get all -o wide
NAME                                   READY   STATUS    RESTARTS   AGE     IP           NODE              NOMINATED NODE   READINESS GATES
pod/minio-0                            1/1     Running   0          2d11h   10.42.0.11   ip-172-31-19-10   <none>           <none>
pod/mariadb-0                          1/1     Running   0          2d11h   10.42.0.12   ip-172-31-19-10   <none>           <none>
pod/spin-redis-57966d86df-qfn9m        1/1     Running   0          2d11h   10.42.0.16   ip-172-31-19-10   <none>           <none>
pod/spin-deck-778577cb65-7m6mw         1/1     Running   0          2d11h   10.42.0.13   ip-172-31-19-10   <none>           <none>
pod/spin-gate-75c99f6b9d-fcgth         1/1     Running   0          2d11h   10.42.0.14   ip-172-31-19-10   <none>           <none>
pod/spin-rosco-86b4b4d6b5-h4vgf        1/1     Running   0          2d11h   10.42.0.20   ip-172-31-19-10   <none>           <none>
pod/spin-orca-84dd94c7f9-ch2t5         1/1     Running   0          2d11h   10.42.0.18   ip-172-31-19-10   <none>           <none>
pod/spin-clouddriver-564d98585-p9m76   1/1     Running   0          2d11h   10.42.0.17   ip-172-31-19-10   <none>           <none>
pod/spin-front50-955856785-tr8pw       1/1     Running   0          2d11h   10.42.0.19   ip-172-31-19-10   <none>           <none>
pod/spin-echo-5b5dc87b4c-ldv97         1/1     Running   0          2d11h   10.42.0.15   ip-172-31-19-10   <none>           <none>

NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE     SELECTOR
service/mariadb            ClusterIP   10.43.69.47     <none>        3306/TCP   2d11h   app=mariadb
service/minio              ClusterIP   10.43.44.26     <none>        9000/TCP   2d11h   app=minio
service/spin-deck          ClusterIP   10.43.68.156    <none>        9000/TCP   2d11h   app=spin,cluster=spin-deck
service/spin-gate          ClusterIP   10.43.230.74    <none>        8084/TCP   2d11h   app=spin,cluster=spin-gate
service/spin-redis         ClusterIP   10.43.102.9     <none>        6379/TCP   2d11h   app=spin,cluster=spin-redis
service/spin-echo          ClusterIP   10.43.147.178   <none>        8089/TCP   2d11h   app=spin,cluster=spin-echo
service/spin-orca          ClusterIP   10.43.27.1      <none>        8083/TCP   2d11h   app=spin,cluster=spin-orca
service/spin-clouddriver   ClusterIP   10.43.181.214   <none>        7002/TCP   2d11h   app=spin,cluster=spin-clouddriver
service/spin-rosco         ClusterIP   10.43.187.43    <none>        8087/TCP   2d11h   app=spin,cluster=spin-rosco
service/spin-front50       ClusterIP   10.43.121.22    <none>        8080/TCP   2d11h   app=spin,cluster=spin-front50

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS    IMAGES                                                   SELECTOR
deployment.apps/spin-redis         1/1     1            1           2d11h   redis         gcr.io/kubernetes-spinnaker/redis-cluster:v2             app=spin,cluster=spin-redis
deployment.apps/spin-deck          1/1     1            1           2d11h   deck          docker.io/armory/deck:2.14.0-5f306f6-df9097d-rc6         app=spin,cluster=spin-deck
deployment.apps/spin-gate          1/1     1            1           2d11h   gate          docker.io/armory/gate:1.14.0-42ccb4f-a2428e6-rc5         app=spin,cluster=spin-gate
deployment.apps/spin-rosco         1/1     1            1           2d11h   rosco         docker.io/armory/rosco:0.16.0-7c38ed6-508e253-rc5        app=spin,cluster=spin-rosco
deployment.apps/spin-orca          1/1     1            1           2d11h   orca          docker.io/armory/orca:2.12.0-67f03ef-c3b6f15-rc8         app=spin,cluster=spin-orca
deployment.apps/spin-clouddriver   1/1     1            1           2d11h   clouddriver   docker.io/armory/clouddriver:6.5.1-f969aaf-2f123de-rc6   app=spin,cluster=spin-clouddriver
deployment.apps/spin-front50       1/1     1            1           2d11h   front50       docker.io/armory/front50:0.21.0-cca684d-4e0f6fc-rc5      app=spin,cluster=spin-front50
deployment.apps/spin-echo          1/1     1            1           2d11h   echo          docker.io/armory/echo:2.10.0-48991a0-e3df630-rc6         app=spin,cluster=spin-echo

NAME                                         DESIRED   CURRENT   READY   AGE     CONTAINERS    IMAGES                                                   SELECTOR
replicaset.apps/spin-redis-57966d86df        1         1         1       2d11h   redis         gcr.io/kubernetes-spinnaker/redis-cluster:v2             app=spin,cluster=spin-redis,pod-template-hash=57966d86df
replicaset.apps/spin-deck-778577cb65         1         1         1       2d11h   deck          docker.io/armory/deck:2.14.0-5f306f6-df9097d-rc6         app=spin,cluster=spin-deck,pod-template-hash=778577cb65
replicaset.apps/spin-gate-75c99f6b9d         1         1         1       2d11h   gate          docker.io/armory/gate:1.14.0-42ccb4f-a2428e6-rc5         app=spin,cluster=spin-gate,pod-template-hash=75c99f6b9d
replicaset.apps/spin-rosco-86b4b4d6b5        1         1         1       2d11h   rosco         docker.io/armory/rosco:0.16.0-7c38ed6-508e253-rc5        app=spin,cluster=spin-rosco,pod-template-hash=86b4b4d6b5
replicaset.apps/spin-orca-84dd94c7f9         1         1         1       2d11h   orca          docker.io/armory/orca:2.12.0-67f03ef-c3b6f15-rc8         app=spin,cluster=spin-orca,pod-template-hash=84dd94c7f9
replicaset.apps/spin-clouddriver-564d98585   1         1         1       2d11h   clouddriver   docker.io/armory/clouddriver:6.5.1-f969aaf-2f123de-rc6   app=spin,cluster=spin-clouddriver,pod-template-hash=564d98585
replicaset.apps/spin-front50-955856785       1         1         1       2d11h   front50       docker.io/armory/front50:0.21.0-cca684d-4e0f6fc-rc5      app=spin,cluster=spin-front50,pod-template-hash=955856785
replicaset.apps/spin-echo-5b5dc87b4c         1         1         1       2d11h   echo          docker.io/armory/echo:2.10.0-48991a0-e3df630-rc6         app=spin,cluster=spin-echo,pod-template-hash=5b5dc87b4c

NAME                       READY   AGE     CONTAINERS   IMAGES
statefulset.apps/minio     1/1     2d11h   minio        minio/minio
statefulset.apps/mariadb   1/1     2d11h   mariadb      mariadb:10.4.12-bionic
```

To list all of the pods:

```bash
$ kubectl -n spinnaker get pods
NAME                               READY   STATUS    RESTARTS   AGE
minio-0                            1/1     Running   0          2d11h
mariadb-0                          1/1     Running   0          2d11h
spin-redis-57966d86df-qfn9m        1/1     Running   0          2d11h
spin-deck-778577cb65-7m6mw         1/1     Running   0          2d11h
spin-gate-75c99f6b9d-fcgth         1/1     Running   0          2d11h
spin-rosco-86b4b4d6b5-h4vgf        1/1     Running   0          2d11h
spin-orca-84dd94c7f9-ch2t5         1/1     Running   0          2d11h
spin-clouddriver-564d98585-p9m76   1/1     Running   0          2d11h
spin-front50-955856785-tr8pw       1/1     Running   0          2d11h
spin-echo-5b5dc87b4c-ldv97         1/1     Running   0          2d11h
```

To see information about a specific pod:

```bash
$ kubectl -n spinnaker describe pod spin-gate-75c99f6b9d-fcgth
Name:         spin-gate-75c99f6b9d-fcgth
Namespace:    spinnaker
Priority:     0
Node:         ip-172-31-19-10/172.31.19.10
Start Time:   Tue, 18 Feb 2020 16:49:51 +0000
Labels:       app=spin
              app.kubernetes.io/managed-by=halyard
              app.kubernetes.io/name=gate
              app.kubernetes.io/part-of=spinnaker
              app.kubernetes.io/version=2.18.0
              cluster=spin-gate
              pod-template-hash=75c99f6b9d
Annotations:  <none>
Status:       Running
IP:           10.42.0.14
IPs:
  IP:           10.42.0.14
Controlled By:  ReplicaSet/spin-gate-75c99f6b9d
Containers:
  gate:
    Container ID:   containerd://86aeeaa76477b83a36466f9267c3319caca7ea410928a9d5206d1e1e893cb850
    Image:          docker.io/armory/gate:1.14.0-42ccb4f-a2428e6-rc5
    Image ID:       docker.io/armory/gate@sha256:29fe06df04a21cb00a0cd94af95db8c441b42078b94648af07a46a98264057aa
    Port:           8084/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Tue, 18 Feb 2020 16:50:29 +0000
    Ready:          True
    Restart Count:  0
    Readiness:      exec [wget --no-check-certificate --spider -q http://localhost:8084/api/v1/health] delay=0s timeout=1s period=10s #success=1 #failure=3
    Environment:
      SPRING_PROFILES_ACTIVE:  local
    Mounts:
      /opt/spinnaker/config from spin-gate-files-1546480033 (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from default-token-tj4cz (ro)
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
Volumes:
  spin-gate-files-1546480033:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  spin-gate-files-1546480033
    Optional:    false
  default-token-tj4cz:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  default-token-tj4cz
    Optional:    false
QoS Class:       BestEffort
Node-Selectors:  <none>
Tolerations:     node.kubernetes.io/not-ready:NoExecute for 300s
                 node.kubernetes.io/unreachable:NoExecute for 300s
Events:          <none>
```

And to see the logs for a given pod:

```bash
$ kubectl -n spinnaker logs -f spin-gate-75c99f6b9d-fcgth
2020-02-21 01:06:20.802  INFO 1 --- [applications-10] c.n.s.g.s.internal.Front50Service        : ---> HTTP GET http://spin-front50.spinnaker:8080/v2/applications?restricted=false
2020-02-21 01:06:20.802  INFO 1 --- [-applications-9] c.n.s.g.s.internal.ClouddriverService    : ---> HTTP GET http://spin-clouddriver.spinnaker:7002/applications?restricted=false&expand=true
2020-02-21 01:06:20.805  INFO 1 --- [-applications-9] c.n.s.g.s.internal.ClouddriverService    : <--- HTTP 200 http://spin-clouddriver.spinnaker:7002/applications?restricted=false&expand=true (2ms)
2020-02-21 01:06:20.806  INFO 1 --- [applications-10] c.n.s.g.s.internal.Front50Service        : <--- HTTP 200 http://spin-front50.spinnaker:8080/v2/applications?restricted=false (4ms)
2020-02-21 01:06:25.808  INFO 1 --- [applications-10] c.n.s.g.s.internal.Front50Service        : ---> HTTP GET http://spin-front50.spinnaker:8080/v2/applications?restricted=false
2020-02-21 01:06:25.808  INFO 1 --- [-applications-9] c.n.s.g.s.internal.ClouddriverService    : ---> HTTP GET http://spin-clouddriver.spinnaker:7002/applications?restricted=false&expand=true
2020-02-21 01:06:25.810  INFO 1 --- [-applications-9] c.n.s.g.s.internal.ClouddriverService    : <--- HTTP 200 http://spin-clouddriver.spinnaker:7002/applications?restricted=false&expand=true (2ms)
2020-02-21 01:06:25.813  INFO 1 --- [applications-10] c.n.s.g.s.internal.Front50Service        : <--- HTTP 200 http://spin-front50.spinnaker:8080/v2/applications?restricted=false (4ms)
```

## Uninstalling K3s
* This will kill your kubernetes cluster: `/usr/local/bin/k3s-killall.sh`

## Uninstall Minnaker for OSX
* Delete the `spinnaker` and `spinnaker-operator` namespace.  
```bash
kubectl --context docker-desktop delete ns spinnaker
kubectl --context docker-desktop delete ns spinnaker-operator
```
* (Optionally) delete the `ingress-nginx` namespace: `kubectl --context docker-desktop delete ns ingress-nginx`
* (Optionally) delete the local resources (including all pipeline defs): `rm -rf ~/minnaker`
