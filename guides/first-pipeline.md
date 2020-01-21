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
1. Adding a parameter to indicate the number of instances for the prod environment.
1. Adding an option to skip the test environment, using a parameter.
1. Adding a webhook trigger to our application, and triggering it manually
1. Triggering a pipeline without a webhook trigger, using a webhook

## Prerequisities

This document assumes that you have the following:

* Can log into the Spinnaker UI (should be accessible at `https://<your-minnaker-ip-or-hostname>`)
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
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
        nginx.ingress.kubernetes.io/rewrite-target: /
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
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
        nginx.ingress.kubernetes.io/rewrite-target: /
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
        traefik.ingress.kubernetes.io/rule-type: PathPrefixStrip
        nginx.ingress.kubernetes.io/rewrite-target: /
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
    1. In the "Account" dropdown, select "spinnaker"
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
* Go to `https://<your-minnaker-ip-or-hostname>/dev/hello-today`, and you should see your app.

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
    1. In the pipeline layout section at the top of the page, click on "Manual Judgment: Deploy to Test" (you're probably already here)
    1. Click "Add stage".  _Notice how the stage is dependent on the stage you had selected when you added the stage (the manual judgment stage)._
    1. In the "Type" dropdown, select "Deploy (Manifest)"
    1. Update the "Stage Name" field to be "Deploy Test"
    1. In the "Account" dropdown, select "spinnaker"
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

## Add on manual judgment and wait stage and blue/green prod deployment

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

---
### Background: ReplicaSets vs. Deployments, and Services

At this point, it may be helpful to get a little bit more background about Kubernetes ReplicaSets, Deployments, and Services in Kubernetes

#### ReplicaSets

In Kubernetes, a `ReplicaSet` object is an object that defines an identical set of pods.

Here's how this works:

* The section under `spec.template` is the pod spec - this defines how Kubernetes should create each of the individual pods
* The pod spec has some set of labels, that get attached to each of the pods owned by the ReplicaSet
* The ReplicaSet also has two other relevant fields:
  * The `spec.replicas` field indicates how many _replicas_, or instances, of the pod to create
  * The `spec.selector.matchLabels` dictionary defines how the ReplicaSet identifies the pods that are owned by it.
* In the Kubernetes cluster, there is a ReplicaSet controller that looks at all of the Kubernetes ReplicaSets and ensures that Pod objects get created in the Kubernetes cluster to match.
* Each Pod that is owned by a ReplicaSet must have all of the labels indicated in the ReplicaSet's `spec.selector.matchLabels` dictionary.  The pods may have additional fields that are not in the `matchLabels` dictionary.
* Therefore, if you want some set of pods to match some pod definition, you can create a ReplicaSet and the ReplicaSet controller will create those objects for you.

The key point here is that a ReplicaSet defines a set of identical pods, which have the same pod spec.  A ReplicaSet's pod spec **cannot** be changed (aside from adding/removing labels and metadata - more on this later) - you cannot, for example, change the Docker image used for a given ReplicaSet.  

It may be helpful to think of a ReplicaSet managing or _owning_ a set of Pods

#### Deployments

Because of the above limitations on changing ReplicaSets, the Kubernetes Deployment object was created.

In Kubernetes, a `Deployment` object is an object that is used to orchestrate ReplicaSets.

Here's how this works:

* A Deployment object will look very similar to a ReplicaSet, with a few key differences
* A Deployment's pod spec **can** be changed
* The Deployment object will be responsible for the creation and manipulation of ReplicaSets
  * There is a Kubernetes Deployment controller that looks at your Deployment objects and creates ReplicaSets to match
  * For example, when you first define a Deployment, Kubernetes will take the pod spec and use it to create a ReplicaSet that has the same pod spec
  * If you then update that Deployment with a different Pod spec, Kubernetes will create a new ReplicaSet matching the new Pod spec
  * Kubernetes will also handle scaling up the new ReplicaSet and scaling down the old ReplicaSet, according to other metadata in the Deployment object (rollout strategies)
* Each pod that gets created by the ReplicaSets that are owned by a given Deployment will (and must) a set of labels including all of the labels in the Deployment object's  `spec.selector.matchLabels` dictionary.  They may have additional labels.

It's helpful to think of a Deployment managing or _owning_ a set of ReplicaSets

#### Services

A Kubernetes `Service` is essentially an internal load balancer (or reverse proxy) in Kubernetes.  By default, a Kubernetes Service will create an internal IP address (accessibile within the Kubernetes cluster) through which a set of pods are load balanced (there are also options to create external load balancers).

Here's how this works:

* A Service has a `spec.selector` field that has a set of Kubernetes labels.
* The Service will load balance all pods that have all of the labels on the spec.selector.

#### Example 1: Deployment (Rollng Deployment)

Say we have the following resources:

* A Deployment "backend"
  * Which creates pods with the following labels:
    * `application: backend`
    * `lb: my-backend`
  * a which has the following matchLabels:
    * `application: backend`

* A Service "my-backend-loadbalancer" with the following selector:
  * `lb: my-backend`

The service will load balancer all of the pods, because they all have the labels specified in the selector.

Then, if we want to update to a new version of our application, we can update the pod spec with the new Docker image, and Kubernetes will stand up a new ReplicaSet with the new pod spec, and scaled down the old ReplicaSet to 0 instances.  This is a rolling deployment, and this is what we did for the dev and test deployments in our pipeline.

#### Example 2: ReplicaSet (Blue / Green Deployment)

Say we have the following resources:

* A ReplicaSet "frontend-001"
  * Which creates pods with the following labels:
    * `application: frontend`
    * `version: 001`
    * `lb: my-loadbalancer`
    * `status: active`
  * a which has the following matchLabels:
    * `application: frontend`
    * `version: 001`

* A second ReplicaSet "frontend-002"
  * Which creates pods with the following labels:
    * `application: frontend`
    * `version: 002`
    * `lb: my-loadbalancer`
  * and which has the following matchLabels:
    * `application: frontend`
    * `version: 002`

* A Service "my-frontend-loadbalancer" with the following selector:
  * `lb: my-loadbalancer`

* A second Service "my-frontend-active-loadbalancer" with the following selector:
  * `status: active`

Then the we will have the following behavior:
* The service "my-frontend-loadbalancer" will load balance all pods from both ReplicaSets, because all pods have the labels in its selector
* The service "my-frontend-aftive-loadbalancer" will load balance only pods from the ReplicaSet "frontend-001", because only those pods match the selector `status: active`
* The ReplicaSets are able to track which pods they own, **completely independent of load balancing behavior.**

In order to perform a blue/green deployment with "my-frontend-active-loadbalancer", we have two options:

* We can modify the selector on the loadBalancer (for example, change it from `status: active` to something else)
* We can modify the labels on the ReplicaSet (for example, add the `status:active` label to the "frontend-002" ReplicaSet and remove the label from the "frontend-001" ReplicaSet)

Spinnaker has a native capability to perform this latter option.  This is what we did for our production pipeline rollout.

### Spinnaker: ReplicaSets vs. Deployments

In Kubernetes, Deployments can be used to handle the rollouts of your application: if you have version A of your application, and want to update it to version B of your application, you update your Deployment specification and Kubernetes will handle creating / updating the ReplicaSets to handle the upgrade in a rolling fashion.

Spinnaker is able to directly use this mechanism, and when you use Spinnaker to create Deployments, your pods will follow whatever pattern Kuberntes uses to meet your Kubernetes Deployment pattern.  Spinnaker also adds annotations to be able to roll back to previous iterations (we'll see this later on).

If we want more control of our application rollout - for example to do a Blue/Green deployment - then Spinnaker can also directly interact with Kubernetes ReplicaSets.  Then, if we add the proper annotations to our ReplicaSets to indicate what Service they *should* be dynamically attached to / detached from, then Spinnaker will do the following:

* Look at the desired Service
* Look at the selector on the desired Service
* If attaching the ReplicaSet pods to the Service, add all of the relevant labels to the ReplicaSet pod spec
* If detaching the ReplicaSet from the Service, remove all of the relevant labels from the ReplicaSet pod spec.

---

## Adding parameters to indicate the number of instances for production

Now, we're going to add an additional parameter to our pipeline, and use those parameters to define how many instances of our app we want in production.

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Add the parameter to your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. Click on the "Configuration" icon on the left side of the pipeline
1. Add a 'prod_count' parameter:
    1. Click "Add Parameter" (in the middle of the page)
    1. Specify "prod_count" as the Name
    1. Check the "Required" checkbox
    1. Check the "Pin Parameter" checkbox
    1. Add a Default Value of "4"
1. Click "Save Changes"

Update the prod manifest to use your parameter:

1. Click on the "Deploy Prod" stage
1. In the large Kubernetes manifest field, find the `replicas` field
1. Replace the `replicas` field with this:

    ```yml
    replicas: '${ #toInt( parameters.prod_count ) }'
    ```

1. Click "Save Changes"

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Specify an image tag (`monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, or `sunday`)
1. Specify some number of instances for your prod deployment
1. Click "Run"

When your pipeline gets to the prod deployment (you'll have to approve the manual judgment), notice how the number of instances in the prod deployment match your parameter.  Note the syntax here - we're providing this field as a string in the parameter, and have to explicitly convert it to an integer in the SpEL (Spring Expression Language) field.  In this case, we are using a helper function provided by Spinnaker - more of these are documented on the Spinnaker document [Pipeline Expression Reference](https://www.spinnaker.io/reference/pipeline/expressions/).

## Adding an option to skip the test environment, using a parameter

We can use logic to determine whether a stage gets run or not.

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Add the parameter to your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. Click on the "Configuration" icon on the left side of the pipeline
1. Add a 'prod_count' parameter:
    1. Click "Add Parameter" (in the middle of the page)
    1. Specify "deploy_test" as the Name
    1. Select the "Required" checkbox
    1. In the "Default Value" field specify `yes`
    1. Select the "Show Options" checkbox
    1. In the "Options" section, enter these two values (press "Add New Option" to add the second one):
      * `yes`
      * `no`
1. Click "Save Changes"

Then, configure the stage to be skippable:

1. Click on the "Deploy Test" stage
1. Scroll down to the bottom, and check the "Conditional on Expression" checkbox
1. In the field that pops up, specify this:

    ```java
    ${parameters['deploy_test'] == 'yes'}
    ```

1. Click "Save Changes"

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Specify an image tag (`monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, or `sunday`)
1. Specify some number of instances for your prod deployment
1. Select "no" in the 'deploy_test' field
1. Click "Run"

Note these things:

* You can, generally, reference parameters (and other fields using either dot notation (`parameters.deploy_test`) or dictionary lookup notation (`parameters['deploy_test']`).
* The help text for the conditional on expression stage may say you don't need the `${}`.  You should still use it.
* Spring Expression Language expects Java syntax between the curly brackets: `${JAVA EXPRESSION HERE}`
* When you trigger the pipeline through the UI, you will get the dropdown options.  Later on, when we trigger the pipeline via a webhook trigger, you won't get these options - if you don't specify *exactly* `yes`, the stage will get skipped.  An alternative option for the conditional to only skip the stage on a 'no' might be:
  * `${parameters['deploy_test'] != 'no'}`
  * More complex conditionals, such as those that are case insensitive

## Adding a webhook trigger to our application

Now, let's configure our pipeline so that it can be triggered from an external system.  There are a number of ways to achieve this; in this document, we will cover two different types of webhooks.

The first mechanism is to expose the pipeline on an **unauthenticated** webhook endpoint (note that we can still specify _plaintext_ verification fields that can be used to prevent the pipeline from being triggered by just anybody).

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Add the parameter to your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. Click on the "Configuration" icon on the left side of the pipeline
1. Scroll down to the "Automated Triggers" section of the pipeline
1. Click "Add Trigger"
1. In the dropdown, select "Webhook trigger"
1. In the "Source" field, type `my-first-pipeline`.  Note that under the field, a URL will get populated that will look like this:
`https://<your-minnaker-url>/api/v1/webhooks/webhook/my-first-pipeline`.  Record this URL.
1. Click "Save Changes"

Now, trigger the pipeline:

1. Go to a bash/shell terminal (this can be run from Minnaker itself), and run this command:

    ```bash
    curl -k -X POST -H 'content-type:application/json' -d '{}' https://<your-minnaker-url>/api/v1/webhooks/my-first-pipeline
    ```

1. This is the same command, spread out across multiple lines (`\` allows you to split a shell command into multiple lines, **as long as there are no spaces after the `\`) - you can run this instead.

    ```bash
    curl -k \
      -X POST \
      -H 'content-type:application/json' \
      -d '{}' \
      https://<your-minnaker-url>/api/v1/webhooks/my-first-pipeline
    ```

    These are what each of the flags mean:

    * `-k`: Skip TLS certificate validation (since Minnaker uses a self-signed certificate)
    * `-X POST`: Submit an HTTP POST instead of the default GET
    * `-H 'content-type:application/json'`: Add an HTTP header with key `content-type` and value `application/json` indicating that we're submitting a JSON object to the API
    * `-d '{}'`: The actual JSON object that we're submitting (in this case, an empty JSON object).  Note the single quotes surrounding the JSON object; this is so we can use double quotes inside the object without escaping.
    * The actual URL to submit the request to.

1. In the Spinnaker UI, note that the pipeline gets started.  Also note that the "Deploy Test" stage runs - this is because the default value for that parameter is "yes" (unless you've changed it).

1. You can also trigger the pipeline with parameters:

    ```bash
    curl -k \
      -X POST \
      -H 'content-type:application/json' \
      -d '{
            "parameters": {
              "tag":"tuesday",
              "prod_count": "5"
            }
          }' \
      https://<your-minnaker-url>/api/v1/webhooks/my-first-pipeline
    ```

Now, add a payload constraint to the trigger:

1. Go back to your pipeline configuration, to the trigger section
1. Click "Add payload constraint" under your webhook trigger.
1. Specify the "key" as `secret` and the value as `hunter2`

And trigger our pipeline (again, from a bash/shell terminal)

  ```bash
  curl -k \
    -X POST \
    -H 'content-type:application/json' \
    -d '{
          "secret": "hunter2",
          "parameters": {
            "tag":"tuesday",
            "prod_count": "5"
          }
        }' \
    https://<your-minnaker-url>/api/v1/webhooks/my-first-pipeline
  ```

Also try the following, which will return a successful response, but will fail to trigger the pipeline because we don't have the validator field:

  ```bash
  curl -k \
    -X POST \
    -H 'content-type:application/json' \
    -d '{
          "parameters": {
            "tag":"tuesday",
            "prod_count": "5"
          }
        }' \
    https://<your-minnaker-url>/api/v1/webhooks/my-first-pipeline
  ```

This is because a given webhook will only trigger a given pipeline if the webhook payload matches all of the payload constraints on the trigger.

Be aware of these things when setting up webhook triggers:

* Webhook trigger endpoints are essentially unauthenticated.  You can add validator fields, but these are plaintext in the Spinnaker pipeline configuration and should not be considered a security feature.
* You can have multiple pipelines triggering off the same endpoint.  You can, optionally, differentiate these by different payload constraints on different pipelines (for example, you could have a payload constraint that is `environment`, and configure different pipelines to trigger based on what the value of that payload constraint is).
* You can have multiple webhook triggers for a given pipeline.
* You can inject additional metadata into the pipeline that isn't exposed through a parameter, through additional fields in the trigger.  All fields in the triggering webhook will be available for usage in the pipeline through SpEL.

## Triggering a pipeline without a wehook trigger, with a webhook

In addition to the above trigger, every time you click "Start Manual Execution" through the Spinnaker UI, your browser is making an API call, acting as you, to the Spinnaker (Gate) API.  You can use the same API to trigger pipelines in an authenticated manner.

**Limitation: This only works if you are able to authenticate, which is trivial when your Spinnaker cluster is configured with basic auth or LDAP, and much harder when it's configured with SAML or OAuth2.0 authentication.  If using one of the latter two, you must set up x509 client certificate authentication to use this capability**

Here's how you do this:

1. Come up with your basic auth string.  Take your **Basic Auth** or **LDAP** username/password combination, with a colon between them, and run them through base64.  For example:

```bash
$ echo -n 'admin:my-new-password' | base64
YWRtaW46bXktbmV3LXBhc3N3b3Jk
```

_(The `-n` flag is key, as otherwise echo adds an endline to the output, which creates an invalid auth token)_

```bash
curl -k \
  -X POST \
  -H 'authorization: Basic YWRtaW4vbXktbmV3LXBhc3N3b3Jk' \
  -H 'content-type: application/json' \
  -d '{"parameters": {"tag": "tuesday"}}' \
  'https://<your-minnaker-url>/api/v1/pipelines/v2/hello-today/Deploy%20Application'
```

Be aware of these things when using this:

* The path for this is `https://<your-minnaker-url>/api/v1/pipelines/v2/<application-name>/<urlencoded-pipeline-name>`
* For pipelines that have special characters, you should use the URL encoded version of those characters (for example, `' '` (space) is `%20`)
* You cannot pass in arbitrary metadata that doesn't come in in either the `parameters` or `artifacts` fields.
* You must be using LDAP or Basic Auth
* If your cluster is configured for SAML or OAuth2.0, you must also set up X509 client certs, and use that instead

## Adding Dev Roll Backs

TODO: This.

## Adding Production (Blue / Green) Roll Backs

TODO: This.
