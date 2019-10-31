# Setting up Notifications to Slack

Spinnaker supports notifications to Slack (and other places) on these six events:

* Pipeline start
* Pipeline completion
* Pipeline failure
* Stage start
* Stage completion
* Stage failure

## Create a Slack bot user (and get the Slack auth token)

1. Go to your Slack management page, and navigate to "Configure Apps" (or go to https://your-slack-workspace.slack.com/apps/manage)
1. Click on "Custom Integrations"
1. Click on "Bots"
1. Click on "Add to Slack"
1. Give your Slack bot a username (such as `spinnakerbot`)
1. Click "Add bot integration"
1. Copy the "API Token".  Optionally, customize other settings on the Bot configuration.
1. Click "Save Integration"

## Add the Slack bot user to Spinnaker

1. SSH into your Mini-Spinnaker instance
1. Run this command (replace `spinnakerbot` with your Slack bot's username) to add the Slack notification configuration.

    ```bash
    hal config notification slack edit --bot-name spinnakerbot --token
    ```

1. Run this command to enable the Slack notification

    ``bash
    hal config notification slack enable
    ```

1. Run this command to apply your changes

    ```bash
    hal deploy apply
    ```

## Use the Slack notification

In order to notify into a given Slack channel, the Slack bot should be invited into your Slack channel(s).  Then, in a pipeline configuration, on the 'configuration' page, you can configure notifications to those channels for when your pipeline starts, completes, or fails, and you can additionally configure the same notifications on individual stages.
