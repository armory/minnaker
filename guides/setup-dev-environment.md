# Setup Local Debugging for Spinnaker Services

## Minimum System requirements
- Windows or Mac OS X
- 16GB of Memory
- 30GB of Available Storage

This allows you to do something like this:

* OSX/Windows workstation, with an Ubuntu VM running in multipass, with everything directly wired up.
* Some services running locally in your workstation (via IntelliJ)
* All other services running in Minnaker (on the VM)

For example:
* OSX/Windows using IP 192.168.64.1 and the VM using 192.168.64.6
* Orca running on http://192.168.64.1:8083
* All other services running on 192.168.64.6 (for example, Clouddriver will be on http://192.168.64.6:7002)

# Install Instructions

## Mac OS X

* Install [homebrew](https://brew.sh/)

    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    ```

## Windows or Mac OS X

* Install a [JDK](https://adoptopenjdk.net/installation.html) 11.0.8

    * Mac OS X

    ```bash
    brew tap AdoptOpenJDK/openjdk
    brew cask install adoptopenjdk11
    ```

    * Windows [instructions](https://www.oracle.com/java/technologies/javase-jdk11-downloads.html)
    

* Install [Multipass](https://multipass.run/)

    * Mac instructions
    ```bash
    brew cask install multipass
    ```
    * Windows [instructions](https://multipass.run/download/windows)
    
* Install [IntelliJ Community Edition](https://www.jetbrains.com/idea/download/)

    * Mac instructions
    ```bash
    brew cask install intellij-idea-ce
    ```
    * Windows [instructions](https://adoptopenjdk.net/installation.html#x64_win-jdk)

* Install Yarn (installs Node.js if not installed).
    * Mac [instructions](https://classic.yarnpkg.com/en/docs/install#mac-stable)
    ```bash
    brew install yarn
    ```
    * Windows [instructions](https://classic.yarnpkg.com/en/docs/install#windows-stable)

* Install `kubectl`.
    * Mac instructions
    ```bash
    brew install kubectl
    ```
    * Windows [instructions](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-windows)


# Getting Spinnaker Up and Running

Open two terminals one will be for shell access into minnaker-vm the other will be for host machine.
- Windows or Mac OS X terminal will be referred to as [host]
- minnaker-vm terminal will be referred to as [minnaker-vm]

## Install Spinnaker in a Multipass VM

1. [minnaker-vm] Start a multipass vm **with 2 cores, 10GB of memory, 30GB of storage**

    ```bash
    multipass launch -c 2 -m 10G -d 30G --name minnaker-vm
    ```

1. [minnaker-vm] Shell into your multipass vm

    ```bash
    multipass shell minnaker-vm
    ```

1. [minnaker-vm] Download and install Minnaker (use open source, no-auth mode)

    ```bash
    curl -LO https://github.com/armory/minnaker/releases/latest/download/minnaker.tgz
    tar -xzvf minnaker.tgz
    ./minnaker/scripts/no_auth_install.sh -o
    ```

1. [minnaker-vm] When it's done, you'll get the IP address of Minnaker.  Remember this (or you can always just run `cat /etc/spinnaker/.hal/public_endpoint`)

      *(if you accidentally forget to use no auth or open source, you can run `./minnaker/scripts/utils/remove_auth.sh` and `./minnaker/scripts/utils/switch_to_oss.sh`)*

## Prepare Host machine to connect to the Minnaker-VM

1. [minnaker-vm] Run this script to ensure each Spinnaker service gets a K8s LoadBalancer and can be accessed from your host machine.

    ```bash
    ./minnaker/scripts/utils/expose_local.sh
    ```

6. [minnaker-vm] Check on the status of spinnaker

    ```
    kubectl get pods -n spinnaker
    ```
    All pods need to show `1/1` for `READY`.

7. [host] You can now browse to spinnaker at https://192.168.64.6
   - Troubleshooting:
     - `Service Unavailable`: wait until spinnaker starts up, it can take a while to start up (download all docker images) the above step will show you if it is up and running.

8. [minnaker-vm] Expose the service you want to debug (example here is orca)
   ```bash
   ./minnaker/scripts/utils/external_service_setup.sh orca
   ```

   You can also expose multiple services
   ```bash
   ./minnaker/scripts/utils/external_service_setup.sh orca echo
   ```

9. [host] Setup your host config files
   - Create/edit the file `~/.spinnaker/spinnaker-local.yml`, and paste the previously copied output.
    ```
    services:
      front50:
        baseUrl: http://192.168.64.6:8080
      redis:
        baseUrl: http://192.168.64.6:6379
      clouddriver:
        baseUrl: http://192.168.64.6:7002
      orca:
        host: 0.0.0.0
      echo:
        baseUrl: http://192.168.64.6:8089
      deck:
        baseUrl: http://192.168.64.6:9000
      rosco:
        baseUrl: http://192.168.64.6:8087
      gate:
        baseUrl: http://192.168.64.6:8084
    ```
   - Create/edit the config file for the service you are going to debug (example orca).
     - [minnaker-vm] 
        ```bash
        cat /etc/spinnaker/.hal/default/staging/orca.yml
        ```
     - [host] create a `~/.spinnaker/orca.yml` file with the above files contents.

10. Choose a working directory, and go there.  I usually use `~/git/spinnaker`

    ```bash
    mkdir -p ~/git/spinnaker
    cd ~/git/spinnaker
    ```

11. Clone the service you want

    ```bash
    git clone https://github.com/spinnaker/orca.git
    ```

    _or, if you have a Git SSH key set up_

    ```bash
    git clone git@github.com:spinnaker/orca.git
    ```

12. Change the branch

    ```bash
    cd orca
    git branch -a
    ```

    You'll see a list of branches (like `remotes/origin/release-1.22.x`).  The last bit (after the last slash) is the branch name.  Check out that branch.

    ```bash
    git checkout release-1.22.x
    ```

13. Open IntelliJ

14. Open your project

    * If you don't have a project open, you'll see a "Welcome to IntelliJ IDEA".

        1. Click "Open or Import"

        2. Navigate to your directory (e.g., `~/git/spinnaker/orca`)

        3. Click on `build.gradle` and click "Open"

        4. Select "Open as Project"

    * If you already have one or more projects open, do the following:

        1. Use the menu "File" > "Open"

        2. Navigate to your directory (e.g., `~/git/spinnaker/orca`)

        3. Click on `build.gradle` and click "Open"

        4. Select "Open as Project"

15. Wait for the thing to do the thing.  It's gotta load the stuff.

16. Through the next few steps, if you hit an "Unable to find Main" or fields are grayed out, reimport the project:

    1. View > Tool Windows > Gradle

    2. In the Gradle window, right click "Orca" and then click "Reimport Gradle Project"

17. In the top right corner of the project window, there's a "Add Configuration" button.  Click it.

18. Click the little '+' sign in the top left corner, and select "Application"

19. Give it a name.  Like "Main" or "Run Orca"

20. Click the three dots next to "Main Class".  Either wait for it to load and select "Main (com.netflix.spinnaker.orca) or click on "Project" and navigate to `orca > orca-web > src > main > groovy > com.netflix.spinnaker > orca > Main`

21. In the dropdown for "Use classpath of module", select "orca-web_main"

22. Click "Apply" and then "OK"

23. To build and run the thing, click the little green triangle next to your configuration (top right corner, kinda)

Now magic happens.

## Some Cleanup Commands for later

### How to reset your minnaker-vm

[minnaker-vm] Run the following to no longer debug from host

    ```bash
    ./minnaker/scripts/utils/external_service_setup.sh
    ```

### How to stop spinnaker

[host] Run the following to stop the minnaker-vm (spinnaker)

```bash
multipass stop minnaker-vm
```

## [Optional] Setup kubectl on host

1. [minnaker-vm] Get your kubernetes config file

    ```bash
    kubectl config view --raw
    ```

    Example Output:
    ```
    apiVersion: v1
    clusters:
    - cluster:
        certificate-authority-data: YOUR_CERT_HERE
        server: https://127.0.0.1:6443
    name: default
    contexts:
    - context:
        cluster: default
        namespace: spinnaker
        user: default
    name: default
    current-context: default
    kind: Config
    preferences: {}
    users:
    - name: default
    user:
        password: YOUR_PASSWORD_HERE
        username: admin
    ```

1. [host] Save the command output from above command `kubectl config view --raw` to `~/.kube/minnaker` on host machine

1. [minnaker-vm] To get the IP of minnaker-vm

   ```bash
   cat /etc/spinnaker/.hal/public_endpoint
   ```

1. [host] Edit `~/.kube/minnaker` to have the IP address of the minnaker-vm
    New File:
    ```
    apiVersion: v1
    clusters:
    - cluster:
        certificate-authority-data: YOUR_CERT_HERE
        server: https://192.168.64.6:6443
    name: default
    contexts:
    - context:
        cluster: default
        namespace: spinnaker
        user: default
    name: default
    current-context: default
    kind: Config
    preferences: {}
    users:
    - name: default
    user:
        password: YOUR_PASSWORD_HERE
        username: admin
    ```

1. [host] Setup `kubectl` from HOST to check on the deploy

    ```
    export KUBECONFIG=~/.kube/minnaker
    kubectl get pods -n spinnaker

    ```
    or always specify `--kubeconfig ~/.kube/minnaker`
    ```
    kubectl --kubeconfig ~/.kube/minnaker get pods -n spinnaker
    ```

2. [host] Now you can run local kubectl command
   ```bash
   kubectl get pods -n spinnaker
   ```

## Start doing plugin-ey things

Follow the "debugging" section here: https://github.com/spinnaker-plugin-examples/pf4jStagePlugin

notes:
* Create the `plugins` directory in the git repo (e.g., `~/git/spinnaker/orca/plugins`) and put the `.plugin-ref` in there
* If you don't see the gradle tab, you can get to it with View > Tool Windows > Gradle

## Build and test the randomWait stage

This assumes you have a Github account, and are logged in.

1. You *probably* want to work on a fork.  Go to github.com/spinnaker-plugin-examples/pf4jStagePlugin

1. In the top right corner, click "Fork" and choose your username to create a fork.  For example, mine is `justinrlee` so I end up with github.com/justinrlee/pf4jStagePlugin

1. On your workstation, choose a working directory.  For example, `~/git/justinrlee`

    ```bash
    mkdir -p ~/git/justinrlee
    cd ~/git/justinrlee
    ```

1. Clone the repo

    ```bash
    git clone https://github.com/justinrlee/pf4jStagePlugin.git
    ```

    _or, if you have a Git SSH key set up_

    ```bash
    git clone git@github.com:justinrlee/pf4jStagePlugin.git
    ```

1. Check out a tag.

    If you are using Spinnaker 1.19.x, you probably need a 1.0.x tag (1.0.x is compatible 1.19, 1.1.x is compatible with 1.20)
    
    List available tags:
    
    ```bash
    cd pf4jStagePlugin
    git tag -l
    ```

    Check out the tag you want:

    ```bash
    git checkout v1.0.17
    ```

    Create a branch off of it (optional, but good if you're gonna be making changes).  This creates a branch called custom-stage

    ```bash
    git switch -c custom-stage
    ```

1. Build the thing from the CLI

    ```bash
    ./gradlew releaseBundle
    ```

    This will generate an orca .plugin-ref file (`random-wait-orca/build/orca.plugin-ref`).  

1. Copy the `orca.plugin-ref` file to the `plugins` directory in your `orca` repo.

    Create the destination directory - this will depend on where you cloned the orca repo

    ```bash
    mkdir -p ~/git/spinnaker/orca/plugins
    ```

    Copy the file

    ```bash
    cp random-wait-orca/build/orca.plugin-ref ~/git/spinnaker/orca/plugins/
    ```

1. Create the orca-local.yml file in `~/.spinnaker/`

    This tells Spinnaker to enable and use the plugin

    Create this file at `~/.spinnaker/orca-local.yml`:
    
    ```bash
    # ~/.spinnaker/orca-local.yml
    spinnaker:
      extensibility:
        plugins:
          Armory.RandomWaitPlugin:
            enabled: true
            version: 1.0.17
            extensions:
              armory.randomWaitStage:
                enabled: true
                config:
                  defaultMaxWaitTime: 60
    ```

1. In IntelliJ (where you have the Orca project open), Link the plugin project to your current project

    1. Open the Gradle window if it's not already open (View > Tool Windows > Gradle)

    1. In the Gradle window, click the little '+' sign

    1. Navigate to your plugin directory (e.g., `/git/justinrlee/pf4jStagePlugin`), and select `build.gradle` and click Open

1. In the Gradle window, right click "orca" and click "Reimport Gralde Project"

1. In IntelliJ, create a new build configuration

    1. In the top right, next to the little hammer icon, there's a dropdown.  Click "Edit Configurations..."

    1. Click the '+' sign in the top left, and select "Application"

    1. Call it something cool.  Like "Build and Test Plugin"

    1. Select the main class (Either wait for it to load and select "Main (com.netflix.spinnaker.orca) or click on "Project" and navigate to `orca > orca-web > src > main > groovy > com.netflix.spinnaker > orca > Main`)

    1. In the dropdown for "Use classpath of module", select "orca-web_main"

    1. Put this in the "VM Options" field put this: '`-Dpf4j.mode=development`'

    1. In the "Before launch" section of the window, click the '+' sign and add "Build Project"

    1. Select "Build" in the "Before launch" section and click the '-' sign to remove it (you don't need both "Build" and "Build Project")

    1. Click "Apply" and then "OK"

1. Run your stuff.

    1. If the unmodified Orca is still running, click the little stop icon (red square in top right corner)

    1. Select your new build configuration in the dropdown

    1. Click the runicon (little green triangle)

    1. In the console output you should see something that looks like this:

        ```
        2020-04-30 10:17:41.242  INFO 53937 --- [           main] com.netflix.spinnaker.orca.Main          : [] Starting Main on justin-mbp-16.lan with PID 53937 (/Users/justin/dev/spinnaker/orca/orca-web/build/classes/groovy/main started by justin in /Users/justin/dev/spinnaker/orca)
        2020-04-30 10:17:41.245  INFO 53937 --- [           main] com.netflix.spinnaker.orca.Main          : [] The following profiles are active: test,local
        
        ...
        
        2020-04-30 10:17:44.276  WARN 53937 --- [           main] c.n.s.config.PluginsAutoConfiguration    : [] No remote repositories defined, will fallback to looking for a 'repositories.json' file next to the application executable
        2020-04-30 10:17:44.410  INFO 53937 --- [           main] org.pf4j.AbstractPluginManager           : [] Plugin 'Armory.RandomWaitPlugin@unspecified' resolved
        2020-04-30 10:17:44.411  INFO 53937 --- [           main] org.pf4j.AbstractPluginManager           : [] Start plugin 'Armory.RandomWaitPlugin@unspecified'
        2020-04-30 10:17:44.413  INFO 53937 --- [           main] i.a.p.s.wait.random.RandomWaitPlugin     : [] RandomWaitPlugin.start()
        ```

    1. If you see "no class Main.main" or something, in the Gradle window, try right click on "orca" and reimport Gradle project and try again.

1. Test your stuff

    1. Go into the Spinnaker UI (should be http://your-VM-ip:9000)

    1. Go to applications > spin > pipelines

    1. Create a new pipeline

    1. Add stage

    1. Edit stage as JSON (bottom right)

    1. Paste this in there:

        ```json
        {
          "maxWaitTime": 15,
          "name": "Test RandomWait",
          "type": "randomWait"
        }
        ```

    1. Update stage

    1. Save changes

    1. Click back to pipelines (pipelines tab at top)

Magic.  Maybe.  Maybe not.
