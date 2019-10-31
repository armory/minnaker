# Create your first pipeline

We're going to create a demo pipeline that deploys to the Kubernetes cluster included with Minnaker.

We will be deploying a Hello World application that indicates the weekday on which it was deployed.

Note: this pipeline is a training exercise.  Typically, you could configure Spinnaker to deploy to some external Kubernetes cluster where you want your application to live, not the Kubernetes K3s instance that is embedded in Minnaker.

Because we're deploying to the internal K3s cluster, we're going to use Traefik to expose our application on three paths on our Minnaker instance:

* `/dev/hello-today`
* `/stage/hello-today`
* `/prod/hello-today`

Traefik will be rewriting application paths using the `PathPrefixStrip` feature (for example, it will rewrite `/dev/hello-today` to `/`).

## Overview

Through this document, we will be doing the following:

1. Setting up our K3s instance with the namespaces we will be deploying to.
1. Creating a Spinnaker "Application" called **hello-today**
1. Creating the load balancers (service and ingress) for our application (one for each environment) through the UI.
1. Creating a single-stage pipeline that deploys our application to the `dev` environment, and running it.
1. Running the pipeline with a different parameter
1. Adding on additional stages that perform a manual judgment and then deploy to the `test` environment.  And running the pipeline.
1. Adding on additional stages that perform another manual judgment and a wait and then deploy to the `prod` environment with a blue/green deployment.  And running the pipeline.
1. Adding parameters to indicate the number of instances for each environment.
1. Adding an option to skip the staging environment, using a parameter.
1. Adding a webhook trigger to our application

## Prerequisities

This document assumes that you have the following:

* Can log into the Spinnaker UI (should be accessible at http://\<your-minnaker-ip-or-hostname\>)
* Have terminal access to the Mini Spinnaker VM

## Setting up the namespaces

*This step is performed through the CLI*

There are several different viable patterns here:

* Deploying to an existing namespace
* Deploying a namespace at the same time as you deploy resources to the namespace
* Deploying resources to an ephemeral namespace

The first use case is the most common, so we're going to three namespaces first:

* `dev`
* `test`
* `prod`

You can do this from the command line on the Minnaker instance:

```bash
kubectl create ns dev
kubectl create ns test
kubectl create ns prod
```

If you want, you can also create a namespace resource via Spinnaker, either through the UI or through a pipeline that does a `Deploy (Manifest)` with the Namespace manifest in it.

## Create the Application

In Spinnaker, an "Application" is basically a grouping of pipelines and the resources deployed by those pipelines.  An Application can group any set of related resouces, and can group objects across multiple cloud targets (and cloud target types).  Common ways to organize services are:

* One application for each microservice
* One application for a set of microservices that make up a single cohesive business function
* One application for each team

Let's create an application called "hello-today".

1. Log into the Spinnaker UI.
1. Click on "Applications"
1. Click on "Actions" and then "Create Application"
1. Call the application "hello-today" and put in your email address in the "Owner Email" field.
1. Click "Create"

## Create the load balancers

Now that our Spinnaker Application and Kubernetes Namespaces are created, we're going to set up some load balancers.

For each of our environments, we're going to set up two Kubernetes resources:

* A "Service" of type "ClusterIP", which acts as an internal load balancer to access our applications
* An "Ingress", which will configure Traefik to point specific paths on the Minnaker VM to our internal Services

Spinnaker abstracts both Kubernetes Servic and Kubernetes Ingress objects as Spinnaker "Load Balancer" objects, so we'll be creating six total Spinnaker "Load Balancers" (one Ingress and one Service for each of our three Namespaces).

Here's where need to start:

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Infrastructure" tab and the "Load Balancers" subtab.

Then, we'll create our resources in batches of two.

Create the **dev** Service and Ingress

1. Click on "Create Load Balancer"
1. Paste in this:

    ```yml
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: hello-today
      namespace: dev
    spec:
      ports:
        - name: http
          port: 80
          protocol: TCP
          targetPort: 80
      selector:
        lb: hello-today
    ---
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      annotations:
        kubernetes.io/ingress.class: traefik
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
      labels:
        app: hello-today
      name: hello-today
      namespace: dev
    spec:
      rules:
        - http:
            paths:
              - backend:
                  serviceName: hello-today
                  servicePort: http
                path: /dev/hello-today
    ```

1. Click "Create"
1. Click "Close"

Create the **test** Service and Ingress

1. Click on "Create Load Balancer"
1. Paste in this:

    ```yml
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: hello-today
      namespace: test
    spec:
      ports:
        - name: http
          port: 80
          protocol: TCP
          targetPort: 80
      selector:
        lb: hello-today
    ---
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      annotations:
        kubernetes.io/ingress.class: traefik
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
      labels:
        app: hello-today
      name: hello-today
      namespace: test
    spec:
      rules:
        - http:
            paths:
              - backend:
                  serviceName: hello-today
                  servicePort: http
                path: /test/hello-today
    ```

1. Click "Create"
1. Click "Close"

Create the **prod** Service and Ingress

1. Click on "Create Load Balancer"
1. Paste in this:

    ```yml
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: hello-today
      namespace: prod
    spec:
      ports:
        - name: http
          port: 80
          protocol: TCP
          targetPort: 80
      selector:
        lb: hello-today
    ---
    apiVersion: extensions/v1beta1
    kind: Ingress
    metadata:
      annotations:
        kubernetes.io/ingress.class: traefik
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
      labels:
        app: hello-today
      name: hello-today
      namespace: prod
    spec:
      rules:
        - http:
            paths:
              - backend:
                  serviceName: hello-today
                  servicePort: http
                path: /prod/hello-today
    ```

1. Click "Create"
1. Click "Close"

You should now have six items on the "Load Balancers" page.

*You could also create all six resources at once, or one at a time instead of two at a time.*

*Creation of the Service and Ingress could occur also occur through a `Deploy (Manifest)` pipeline stage that has the Service and Ingress resource manifests in it.*

## Create a new pipeline

We're going to start off with a simple "Deploy Application" pipeline, that will have a single stage that deploys the `dev` version of our application.  We're going to be deploying this as a Kubernetes `Deployment` object, which will handle rollouts for us.

Keep in mind that we have already created these resources:

* A `dev` Namespace
* A `hello-today` Service in the `dev` namespace
* A `hello-today` Ingress to expose the application on your Spinnaker instance, on the `/dev/hello-today` endpoint

### Create the pipeline

Here's where need to start:

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Then, actually create the pipeline:

1. In the top right, click the '+' icon (or "+ Create", depending on the size of your browser)
1. Give the pipeline the name "Deploy Application"
1. Add a 'tag' parameter:
    1. Click "Add Parameter" (in the middle of the page)
    1. Specify "tag" as the Name
    1. Check the "Required" checkbox
    1. Check the "Pin Parameter" checkbox
    1. Add a Default Value of "monday" (all lowercase)
1. Add the *Deploy Dev* stage
    1. Click "Add Stage"
    1. In the "Type" dropdown, select "Deploy (Manifest)"
    1. Update the "Stage Name" field to be "Deploy Dev"
    1. In the "Application" dropdown, select "spinnaker"
    1. Select the 'Override Namespace' checkbox, and select 'dev' in the dropdown
    1. In the "Manifest" field, put this (note the `${parameters["tag"]}` field, which will pull in the tag parameter)

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
                - image: 'justinrlee/nginx:${parameters["tag"]}'
                  name: primary
                  ports:
                    - containerPort: 80
        ```

1. Click "Save Changes"

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Click "Run"

Your application should be deployed.  Look at the status of this in three ways:

* Go to the "Infrastructure" tab and "Clusters" subtab, and you should see your application, which consists of a Deployment with a single ReplicaSet.  Examine different parts of this page.
* Go to the "Infrastructure" tab and "Load Balancers" subtab.  Examine different parts of this page (for example, try checking the 'Instance' checkbox so you can see ReplicaSets and Pods attached to your Service)
* Go to http://\<your-minnaker-ip-or-hostname\>/dev/hello-today, and you should see your app.

## Run the pipeline with a different parameter

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Replace "monday" with some other day of the week (like 'tuesday' or 'wednesday')
1. Click "Run"

## Expand the pipeline: Add manual judgment and `test` deployment

Now that we have a running pipelines, let's add a promotion to a higher environment, gated by a manual approval.

Go back to the Spinnaker pipelines page:

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Edit your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. Click on the "Configuration" icon on the left side of the pipeline
1. Add the "Manual Judgment: Deploy to Stage"
    1. Click "Add stage". Note how the stage is set to run at the beginning of the pipeline.
    1. Select "Manual Judgment" from the "Type" dropdown
    1. In the "Stage Name", enter "Manual Judgment: Deploy to Test"
    1. In the "Instructions" field, enter "Please verify Dev and click 'Continue' to continue deploying to Test"
    1. Click in the "Depends On" field at the top, and select your "Deploy Dev" stage.  _Notice how this rearranges the stages so that the manual judgment stage depends on (starts *after*) the dev deployment stage._
    1. Click "Save Changes" in the bottom right.
1. Add the *Deploy Test* stage
    1. In the pieline layout section at the top of the page, click on "Manual Judgment: Deploy to Test" (you're probably already here)
    1. Click "Add stage".  _Notice how the stage is dependent on the stage you had selected when you added the stage (the manual judgment stage)._
    1. In the "Type" dropdown, select "Deploy (Manifest)"
    1. Update the "Stage Name" field to be "Deploy Test"
    1. In the "Application" dropdown, select "spinnaker"
    1. Select the 'Override Namespace' checkbox, and select 'test' in the dropdown
    1. In the "Manifest" field, put this (note the `${parameters["tag"]}` field, which will pull in the tag parameter)

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
                - image: 'justinrlee/nginx:${parameters["tag"]}'
                  name: primary
                  ports:
                    - containerPort: 80
        ```

1. Click "Save Changes"

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Click "Run"

_Notice that we used the exact same manifest; we just selected a different override namespace.  This works because the manifest doesn't have hardcoded namespaces._

Right now, we only have one Kubernetes "Account", called "spinnaker", which refers to the Kubernetes cluster that Spinnaker is running on.

If we have added additional Kubernetes clusters to Spinnaker, we could also (alternately or in addition) configure Spinnaker to deploy to a different Kubernetes cluster by selecting a different option in the "Account" dropdown.

## Add on manual judgment and blue/green `prod deployment

Next, we're going to show a blue/green deployment, which is handled by Spinnaker's traffic management capabilities.  We're going to gate this with both a manual judgment and a wait stage.

Go back to the Spinnaker pipelines page:

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Edit your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. We're going to add two stages that depend on the "Deploy Test" stage.
    1. Add the Manual Judgment Stage:
        1. Click on the "Deploy Test" stage
        1. Click on "Add stage"
        1. Select "Manual Judgment" from the "Type" dropdown
        1. In the "Stage Name", enter "Manual Judgment: Deploy to Prod"
        1. In the "Instructions" field, enter "Please verify Test and click 'Continue' to continue deploying to Prod"
        1. Click "Save Changes" in the bottom right.
    1. Add the Wait Stage:
        1. Click on the "Deploy Test" stage
        1. Click on "Add stage"
        1. Select "Wait" from the "Type" dropdown
        1. In the "Stage Name", enter "Wait 30 Seconds"
        1. Click "Save Changes" in the bottom right.
        1. _Notice how we now have two stages that "Depend On" the "Deploy Test" stage.  Once the "Deploy Test" stage finishes, both of these stages will start.  A stage can have one or more stages that depend on it._
1. Now we're going to add the Kubernetes blue/green "Deploy Prod" stage
    1. Click on the "Manual Judgment: Deploy to Prod" stage
    1. Click on "Add Stage"
    1. In the "Type" dropdown, select "Deploy (Manifest)"
    1. Update the "Stage Name" field to be "Deploy Prod"
    1. Click in the empty "Depends On" field, and select "Wait 30 Seconds".  _Notice how this stage depends on both the wait and manual judgment stages - it will wait till both are complete before it starts.  A stage can depend on one more or stages._
    1. In the "Account" dropdown, select "Spinnaker"
    1. Check the "Override Namespace" checkbox and select "prod" from the "Namespace" dropdown
    1. In the manifest field, enter this (_notice that this manifest is different from the other two manifests - this is explained below_).

        ```yml
        apiVersion: apps/v1
        kind: ReplicaSet
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
            spec:
              containers:
              - image: 'justinrlee/nginx:${parameters["tag"]}'
                name: primary
                ports:
                - containerPort: 80
                  protocol: TCP
        ```

    1. Below the manifest block, go to the "Rollout Strategy Options"
    1. Check the box for "Spinnaker manages traffic based on your selected strategy"
    1. Select "prod" from the "Service Namespace" dropdown
    1. Select "hello-today" from the "Service(s)" dropdown
    1. Check the "Send client requests to new pods" checkbox
    1. Select "Red/Black" from the "Strategy" dropdown
    1. Click "Save Changes" in the bottom right.

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Click "Run"

TODO: Explain ReplicaSet vs. Deployment

## Adding parameters to indicate the number of instances for each environment

TODO: This.

## Adding an option to skip the staging environment, using a parameter

TODO: This.

## Adding a webhook trigger to our application

TODO: This.