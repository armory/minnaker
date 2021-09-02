# Deploy a Jenkins-built container to Kubernetes with Spinnaker (with ECR)

### This document is still in *draft* form

In this codelab, we will perform the following:

* Configure Spinnaker with a GitHub credential

Then, we'll build out the process to do the following:
* Jenkins build a Docker image
* Jenkins push the Docker image to ECR (alternately, to Docker Hub)
* Jenkins send a webhook to Spinnaker to trigger a Spinnaker pipeline, with a Docker image artifact
* Spinnaker receive the webhook, pull a Kubernetes manifest from GitHub, hydrate the Docker image, and deploy the manifest to a Kubernetes cluster

We assume the following in this document:
* You have the following set up and configured:
  * A Kubernetes cluster
  * A Jenkins instance
  * A Spinnaker instance that has access to your Kubernetes cluster
  * A GitHub account or a GitHub Enterprise instance with an account
* Jenkins slaves are configured with the Docker daemon (to build Docker images)
* Jenkins slaves have credentials to push to your Docker registry of choice
* Your Kubernetes cluster is able to run images from your Docker registry

## Set up
### Configure Spinnaker with GitHub credentials

(OSS documentation for this is here: https://www.spinnaker.io/setup/artifacts/github/)

First, create a credential for Spinnaker to use to access GitHub:

* In your GitHub, go to Settings (click on your user icon in the top right) > Developer Settings > Personal Access Tokens
* Click "Generate new token"
* Give your token a name, and give it the 'repo' access
* Copy the token down

Then, using Halyard, add the credential to Spinnaker as "GitHub artifact Account" (these all take place in Halyard):

* In your Halyard, enable the artifacts feature:

  ```bash
  hal config features edit --artifacts true
  ```

* In your Halyard, enable the new artifact UI feature:

  ```bash
  hal config features edit --artifacts-rewrite true
  ```

* Enable the GitHub artifact account type:

  ```bash
  hal config artifact github enable
  ```

* Add the credential as a "GitHub Artifact Account":

  *You will be prompted for a token; enter your token at the prompt.*

  ```bash
  hal config artifact github account add my-github-credential \
    --token
  ```

* Appl (Deploy) your changes:

  ```bash
  hal deploy apply
  ```

## Create an ECR Repository

* In the AWS console, go to Compute > ECR
* Click "Create repository"
* Give it a name and namespace (for example, hello-world/nginx)
* You'll get a repository formatted like this: `111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx`

## Configure Jenkins to push to the repository

### Set up Cross-Account Access

Assuming Jenkins is running in a different AWS account from your ECR repository, you'll need to set up cross-account access.

* Get the AWS account ID for the AWS account where Jenkins is running (you can use the command `aws sts get-caller-identity` to see what account you're accessing from; for example, an ARN of `arn:aws:sts::222233334444:assumed-role/ec2-role/i-00001111222233334` means you're in `222233334444`)
* Log into to the AWS console account where your ECR repository exists, and go to Compute > ECR
* Click on your repository
* On the left side, click on "Permissions"
* Edit the policy JSON to include this:
    
    ```json
    {
      "Version": "2008-10-17",
      "Statement": [
        {
          "Sid": "AllowCrossAccountPush",
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::222233334444:root"
          },
          "Action": [
            "ecr:BatchCheckLayerAvailability",
            "ecr:CompleteLayerUpload",
            "ecr:GetDownloadUrlForLayer",
            "ecr:InitiateLayerUpload",
            "ecr:PutImage",
            "ecr:UploadLayerPart"
          ]
        }
      ]
    }
    ```

    *This will allow entities in the `222233334444` AWS account to push to this repo*

* Save your changes

## Set up ECR Repository Access

**There are many ways to do this; this is an insecure, temporary way to do this (ideally you'd set up use an AWS helper function to dynamically generate Docker creds)**

The machine where you are doing Docker builds will need permissions and credentials to push to your ECR repository.  In this case, this will likely be the Jenkins slave where your Docker builds will be taking place.

* If you don't have an IAM role attached to the EC2 instance, go to the instance in the EC2 console, add an EC2 IAM role (either use an existing role, or create a new role), and add the `AmazonEC2ContainerRegistryFullAccess` policy to the role.

## Build the Docker image in Jenkins

*Something very similar to this could be achieved with the Docker plugin, or whatever other Docker build and push mechanism your organization uses.  This is meant to be more illustrative of the process than efficient; you can tweak this significantly with better build triggers, pipelines, plugins, and so forth.*

In your Jenkins instance, create a new item of type "Freestyle project".  Set up a "Build" step of type "Shell" with something like this:

```bash
# This is a basic 'hello world' index page for nginx
tee index.html <<-'EOF'
hello world
EOF

# This is a basic Dockerfile that starts with nginx, and adds our hello world page
tee Dockerfile <<-'EOF'
FROM nginx:latest
COPY index.html /usr/share/nginx/html/index.html
EOF

TAG=$(date +%s)

# This removes any AWS creds if they're present in the environment; remove this if you want to use the creds baked into Jenkins

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

# Replace 111122223333 with the account ID where your ECR repo is, and the region with the region where your ECR repo is
$(aws ecr get-login --no-include-email --region us-west-2 --registry-ids 111122223333)

# Replace 111122223333 with the account ID where your ECR repo is, and the region with the region where your ECR repo is
docker build . -t 111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:${TAG}

# Replace 111122223333 with the account ID where your ECR repo is, and the region with the region where your ECR repo is
docker push 111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:${TAG}
``` 

Build your Jenkins job, and you should see a new Docker image tag show up in your ECR repo.

## Deploy an initial (static) manifest from Spinnaker

* In Spinnaker, create a new application, then a new pipeline
* Add a stage "Deploy (Manifest)"
* Select your Kubernetes cluster from the Account drop down
* Select the "Override Namespace" checkbox, and select a namespace that Spinnaker is allowed to deploy to
* In the manifest, put this (replace the image with the produced image and tag)

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-today
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-today
  template:
    metadata:
      labels:
        app: hello-today
        lb: hello-today
    spec:
      containers:
        - image: '111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:1581376100'
          name: primary
          ports:
            - containerPort: 80
```

Go to your pipelines page, and trigger the pipeline.  Verify that it deploys (this will validate that Kubernetes can run images from your ECR repo)

This should do the following:
* Start the Spinnaker pipeline
* Deploy the manifest
* Wait for the pods to be fully up

## Update the manifest to use a dynamic image, and add a trigger with a default tag

* Go back to the pipeline configuration.
* In the pipeline stage UI, click on "Configuration" on the left
* Click "Add Trigger"
* Select "Webhook" for the "Type"
* Add "hello-world" to the "source".  This will create a URL like https://your-spinnaker-url/api/v1/webhooks/webhook/hello-world - this is the webhook endpoint used to trigger the pipeline.  Remember this URL.
* Add a payload constraint with a "key" of "secret" and a "value" of "my-secret-value"
* Click on "Artifact Constraints" > Define a new artifact
* Enter these values:
  * Account: "custom-artifact"
  * Type: "docker/image"
  * Name: "hello-world/nginx"
* Check the "Use default artifact" checkbox.  Enter these values:
  * Account: "custom-artifact"
  * Type: "docker/image"
  * Name: "hello-world/nginx"
  * Reference: "111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:1581376100" (replace with a valid tag)
* The artifact will result in a "Display Name" (like "mean-eel-993")
* Navigate back to the "Deploy (Manifest)" stage, and make these changes:
  * Change the image field in the manifest to be just "hello-world/nginx"
  * Add a "Required artifacts to bind" indicating the display name of your artifact

Your full manifest should look like this:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-today
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-today
  template:
    metadata:
      labels:
        app: hello-today
        lb: hello-today
    spec:
      containers:
        - image: hello-world/nginx
          name: primary
          ports:
            - containerPort: 80
```

Trigger the pipeline, and ensure the Docker image in the hydrated manifest is the fully qualified manifest

Here's what this is doing:
* When you run the pipeline, it's looking an input artifact matching this pattern:
    ```json
    {
      "type": "docker/image",
      "name": "hello-world/nginx"
    }
    ```

* Since you are triggering the pipeline manually, it's not finding the input artifact, so it's using the default artifact:
    ```json
    {
      "type": "docker/image",
      "name": "hello-world/nginx",
      "reference": "111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:1581376505"
    }
    ```

* Because your manifest is configured to "Bind" the artifact, it will look for images populated with "hello-world/nginx", and replacing them with the "found" reference (in this case, the reference from the default artifact) before the deployment.

This should do the following:
* Start the Spinnaker pipeline
* Parse the default artifact
* Replace the `hello-world/nginx` with the reference from your passed-in artifact
* Deploy the hydrated manifest
* Wait for the pods to be fully up

## Trigger the pipeline from a CLI

Do another build, and get another Docker image.  For example: `111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:1581376505` (note the different tag).

Then, using the URL from above, as well as the key/value pair, do this from a shell terminal:

```bash
tee body.json <<-EOF
{
  "secret": "my-secret-value",
  "artifacts": [
    {
      "type": "docker/image",
      "name": "hello-world/nginx",
      "reference": "111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:1581376505"
    }
  ]
}
EOF

curl -k -X POST \
  -H 'content-type:application/json' \
  -d @body.json \
  https://your-spinnaker-url/api/v1/webhooks/webhook/hello-world
```

Go to Spinnaker, and your pipeline should trigger with the new tag (check the deployed manifest)

This should do the following:
* Start the Spinnaker pipeline
* Parse the artifact with your generated tag
* Pull the Kubernetes manifest from GitHub (Enterprise)
* Replace the `hello-world/nginx` with the reference from your passed-in artifact
* Deploy the hydrated manifest
* Wait for the pods to be fully up

## Trigger the pipeline from Jenkins

Go back into Jenkins, and add the above curl command to the end of your shell command.  Replace the tag with your dynamically generated tag, so it'll look something like this:

```bash
tee body.json <<-EOF
{
  "secret": "my-secret-value",
  "artifacts": [
    {
      "type": "docker/image",
      "name": "hello-world/nginx",
      "reference": "111122223333.dkr.ecr.us-west-2.amazonaws.com/hello-world/nginx:${TAG}"
    }
  ]
}
EOF

curl -k -X POST \
  -H 'content-type:application/json' \
  -d @body.json \
  https://your-spinnaker-url/api/v1/webhooks/webhook/hello-world
```

Trigger your Jenkins build, and it should do the following:
* Build a new Docker image
* Push it to your ECR repo
* Trigger the Spinnaker pipeline

Then the Spinnaker pipeline will:
* Start the Spinnaker pipeline
* Parse the artifact with your generated tag
* Replace the `hello-world/nginx` with the reference from your passed-in artifact
* Deploy the hydrated manifest

## Put the Kubernetes Manifest in GitHub

Go into Spinnaker to your pipeline, and grab the Kubernetes manifest

Go into your GitHub repo (or create a repo), and create the manifest as a file somewhere in the repo (for example, at `/app/manifests/manifest.yml`).  

It should look something like this:

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-today
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-today
  template:
    metadata:
      labels:
        app: hello-today
        lb: hello-today
    spec:
      containers:
        - image: hello-world/nginx
          name: primary
          ports:
            - containerPort: 80
```

* In Spinnaker, go to your "Deploy (Manifest)" stage, and go down to the "Manifest" section.
* Select "Artifact" for the "Manifest Source"
* Select "Define New Artifact".  Populate these fields:
    * Account: "my-github-credential" (or whatever you specified for the credential name)
    * Content URL: `https://api.github.com/repos/$ORG/$REPO/contents/$FILEPATH` (`https://github.mydomain.com/api/v3/repos/$ORG/$REPO/$FILEPATH` for GHE).  Replace the org, repo, and filepath with relevant entries for your file.  For example:
        * GitHub.com: `https://api.github.com/repos/baxterthehacker/public-repo/contents/path/to/file.yml`.
        * GHE: `https://github.mydomain.com/api/v3/repos/baxterthehacker/public-repo/contents/path/to/file.yml`)

Save the pipeline, and re-trigger the Jenkins build.  This should do the following:

Trigger your Jenkins build, and it should do the following:
* Build a new Docker image
* Push it to your ECR repo
* Trigger the Spinnaker pipeline

Then the Spinnaker pipeline will:
* Start the Spinnaker pipeline
* Parse the artifact with your generated tag
* Pull the Kubernetes manifest from GitHub (Enterprise)
* Replace the `hello-world/nginx` with the reference from your passed-in artifact
* Deploy the hydrated manifest
* Wait for the pods to be fully up

Verify your deployed image is the most recent tag.

## Remove the default artifact

* Go into the configuration for your pipeline
* Go to your artifact constraint, and click the pencil icon
* Uncheck the default artifact checkbox

Save the pipeline.

Do a hard refresh of the page to verify the default artifact is removed (click on the pencil again).

Save the pipeline, and re-trigger the Jenkins build.  This should do the following:

Trigger your Jenkins build, and it should do the following:
* Build a new Docker image
* Push it to your ECR repo
* Trigger the Spinnaker pipeline

Then the Spinnaker pipeline will:
* Start the Spinnaker pipeline
* Parse the artifact with your generated tag
* Pull the Kubernetes manifest from GitHub (Enterprise)
* Replace the `hello-world/nginx` with the reference from your passed-in artifact
* Deploy the hydrated manifest
* Wait for the pods to be fully up