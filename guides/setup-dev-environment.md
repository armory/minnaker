# Plugin / Dev environment

These notes are very unformatted.

Assume OSX with at least 16GB of memory and 30GB available storage

This allows you to do something like this:

* OSX workstation, with an Ubuntu VM running in multipass, with everything directly wired up.
* Some services running locally in your workstation (via IntelliJ)
* All other services running in Minnaker (on the VM)

For example:
* OSX using IP 192.168.64.1 and the VM using 192.168.64.10
* Orca running on http://192.168.64.1:8083
* All other services running on 192.168.64.10 (for example, Clouddriver will be on http;//192.168.64.10:7002)

Prereqs:

* Install a JDK (I don't know what's necessary, but I have OpenJDK 1.8:

    ```
    openjdk version "1.8.0_242"
    OpenJDK Runtime Environment (AdoptOpenJDK)(build 1.8.0_242-b08)
    OpenJDK 64-Bit Server VM (AdoptOpenJDK)(build 25.242-b08, mixed mode)
    ```
* Install Multipass: https://multipass.run/
* Install IntelliJ

## Install Spinnaker in a Multipass VM

1. Start a multipass vm **with 2 cores, 10GB of memory, 30GB of storage**

    ```bash
    multipass launch -c 2 -m 10G -d 30G
    ```

1. Get the name of your multipass vm

    ```bash
    multipass list
    ```

1. Shell into your multipass vm

    ```bash
    multipass shell <vm-name>
    ```

1. Download and install Minnaker (use open source, no-auth mode)

    ```bash
    curl -LO https://github.com/armory/minnaker/releases/latest/download/minnaker.tgz
    tar -xzvf minnaker.tgz
    ./minnaker/scripts/no_auth_install.sh -o
    ```

1.   When it's done, you'll get the IP address of Minnaker.  Remember this (or you can always just run spin_endpoint)

      *(if you accidentally forget to use no auth or open source, you can run `./minnaker/scripts/utils/remove_auth.sh` and `./minnaker/scripts/switch_to_oss.sh`)*

1. Configure Minnaker to listen on all ports:

    ```bash
    ./minnaker/scripts/utils/expose_local.sh
    ```

**Decide which services you want to run locally**

This example uses Orca, but you can run any number of services locally

1. Configure Minnaker to expect the relevant service to be external

    ```bash
    ./minnaker/scripts/utils/external_service_setup.sh orca
    ```

    If you want multiple, specify them space delimited:

    ```bash
    ./minnaker/scripts/utils/external_service_setup.sh orca echo
    ```

    **Every time you run this, it will remove the previous configuration.**

1. Part of the output will be a section that says `Place this file at '~/.spinnaker/spinnaker-local.yml' on your workstation`.  Copy that section (between the lines)

### Switch to your OSX workstation

1. Create/edit the file `~/.spinnaker/spinnaker-local.yml`, and paste the previously copied output.

1. Choose a working directory, and go there.  I usually use `~/git/spinnaker`

    ```bash
    mkdir -p ~/git/spinnaker
    cd ~/git/spinnaker
    ```

1. Clone the service you want

    ```bash
    git clone https://github.com/spinnaker/orca.git
    ```

    _or, if you have a Git SSH key set up_

    ```bash
    git clone git@github.com:spinnaker/orca.git
    ```

1. Change the branch

    ```bash
    cd orca
    git branch -a
    ```

    You'll see a list of branches (like `remotes/origin/release-1.19.x`).  The last bit (after the last slash) is the branch name.  Check out that branch.

    ```bash
    git checkout release-1.19.x
    ```

1. Open IntelliJ

1. Open your project

    * If you don't have a project open, you'll see a "Welcome to IntellJ IDEA".

        1. Click "Open or Import"

        1. Navigate to your directory (e.g., `~/git/spinnaker/orca`)

        1. Click on `build.gradle` and click "Open"

        1. Select "Open as Project"

    * If you already have one or more projects open, do the following:

        1. Use the menu "File" > "Open"

        1. Navigate to your directory (e.g., `~/git/spinnaker/orca`)

        1. Click on `build.gradle` and click "Open"

        1. Select "Open as Project"

1. Wait for the thing to do the thing.  It's gotta load the stuff.

1. In the top right corner of the project window, there's a "Add Configuration" button.  Click it.

1. Click the little '+' sign in the top left corner, and select "Application"

1. Give it a name.  Like "Main" or "Run Orca"

1. Click the three dots next to "Main Class".  Either wait for it to load and select "Main (com.netflix.spinnaker.orca) or click on "Project" and navigate to `orca > orca-web > src > main > groovy > com.netflix.spinnaker > orca > Main`

1. In the dropdown for "Use classpath of module", select "orca-web_main"

1. Click "Apply" and then "OK"

1. To build and run the thing, click the little green triangle next to your configuration (top right corner, kinda)

Now magic happens.

## Start doing plugin-ey things

Follow the "debugging" section here: https://github.com/spinnaker-plugin-examples/pf4jStagePlugin

notes:
* Create the `plugins` directory in the git repo (e.g., `~/git/spinnaker/orca/plugins`) and put the `.plugin-ref` in there
* If you don't see the gradle tab, you can get to it with View > Tool Windows > Gradle