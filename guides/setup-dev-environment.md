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

      *(if you accidentally forget to use no auth or open source, you can run `./minnaker/scripts/utils/remove_auth.sh` and `./minnaker/scripts/utils/switch_to_oss.sh`)*

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

1. Through the next few steps, if you hit an "Unable to find Main" or fields are grayed out, reimport the project:

    1. View > Tool Windows > Gradle

    1. In the Gradle window, right click "Orca" and then click "Reimport Gradle Project"

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
