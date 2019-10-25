# Create your first pipeline

We're going to create a demo pipeline that deploys to the Kubernetes cluster included with Mini-Spinnaker.

We will be deploying a Hello World application that indicates the weekday on which it was deployed.

Note: this pipeline is a training exercise.  Typically, you could configure Spinnaker to deploy to some external Kubernetes cluster where you want your application to live, not the Kubernetes K3s instance that is embedded in Mini-Spinnaker.

Because we're deploying to the internal K3s cluster, we're going to use Traefik to expose our application on three paths on our Mini-Spinnaker instance:

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
1. Adding on additional stages that perform a manual judgment and then deploy to the `stage` environment.  And running the pipeline.
1. Adding on additional stages that perform another manual judgment, and then deploy to the `prod` environment with a blue/green deployment.  And running the pipeline.
1. Adding parameters to indicate the number of instances for each environment.
1. Adding an option to skip the staging environment, using a parameter.
1. Adding a webhook trigger to our application

## Prerequisities

This document assumes that you have the following:

* Can log into the Spinnaker UI (should be accessible at http://<your-mini-spinnaker-ip>)
* Have terminal access to the Mini Spinnaker VM

## Setting up the namespaces

*This step is performed through the CLI*

There are several different viable patterns here:
* Deploying to an existing namespace
* Deploying a namespace at the same time as you deploy resources to the namespace
* Deploying resources to an ephemeral namespace

The first use case is the most common, so we're going to three namespaces first:
* `dev`
* `stage`
* `prod`

You can do this from the command line on the Mini-Spinnaker instance:

```bash
kubectl create ns dev
kubectl create ns stage
kubectl create ns prod
```

(You could also do this with one command: `kubectl create ns dev stage prod`)

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
* An "Ingress", which will configure Traefik to point specific paths on the Mini-Spinnaker VM to our internal Services

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
      type: LoadBalancer
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

Create the **stage** Service and Ingress

1. Click on "Create Load Balancer"
1. Paste in this:

    ```yml
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: hello-today
      namespace: stage
    spec:
      ports:
        - name: http
          port: 80
          protocol: TCP
          targetPort: 80
      selector:
        lb: hello-today
      type: LoadBalancer
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
      namespace: stage
    spec:
      rules:
        - http:
            paths:
              - backend:
                  serviceName: hello-today
                  servicePort: http
                path: /stage/hello-today
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
      type: LoadBalancer
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
1. Click "Add Stage"
1. In the "Type" dropdown, select "Deploy (Manifest)"
1. Update the "Stage Name" field to be "Deploy Dev"
1. In the "Application" dropdown, select "spinnaker"
1. Select the 'Override Namespace' checkbox, and select 'dev' in the dropdown
1. In the "Manifest" field, put this (note the `${parameters['tag']}` field, which will pull in the tag parameter)

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
        - image: 'justinrlee/nginx:${parameters['tag']}'
          name: primary
          ports:
            - containerPort: 80
```

1. Click "Save Changes"

Then, trigger the pipeline:

1. Click back on the "Pipelines" tab at the top of the page
1. Click on "Start Manual Execution" next to your newly created pipeline (you can also click "Start Manual Execution" in the top right, and then select your pipeline in the dropdown)
1. Click Run"

Your application should be deployed.  Look at the status of this in three ways:

* Go to the "Infrastructure" tab and "Clusters" subtab, and you should see your application, which consists of a Deployment with a single ReplicaSet.  Examine different parts of this page.
* Go to the "Infrastructure" tab and "Load Balancers" subtab.  Examine different parts of this page (for example, try checking the 'Instance' checkbox so you can see ReplicaSets and Pods attached to your Service)
* Go to http://\<your-mini-spinnaker-instance-IP\>/dev/hello-today, and you should see your app.

## Add on manual judgment and `stage` deployment

Go back to the Spinnaker pipelines page:

1. Log into the Spinnaker UI
1. Go to the "Applications" tab
1. Click on our "hello-today" application
1. Go to the "Pipelines" tab.

Edit your pipeline:

1. Click on the "Configure" button next to your pipeline (or click on "Configure" in the top right, and select your pipeline)
1. Click on the "Configuration" icon on the left side of the pipeline
1. Add the "Manual Judgment Stage":
    1. Click "Add stage"
    1. Select "Manual Judgment" from the "Type" dropdown
    1. In the "Stage Name", enter "Approve Deployment to Stage"
    1. In the "Instructions" field, enter "Please look at Dev and click 'Continue' to continue deploying to Stage"
    1. Click in the "Depends On" field at the top, and select your "Deploy Dev" stage.  This will make it so that the manual judgment stage starts *after* the dev deployment completes.
    1. Click "Save Changes" in the bottom right.


## Add on manual judgment and blue/green `prod deployment

## Adding parameters to indicate the number of instances for each environment

## Adding an option to skip the staging environment, using a parameter

## Adding a webhook trigger to our application
