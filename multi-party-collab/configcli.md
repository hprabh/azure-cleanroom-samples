# Working with a clean room specification <!-- omit from toc -->

- [Overview](#overview)
- [Define datasources, datasinks and applications](#define-datasources-datasinks-and-applications)
  - [Add a datasource](#add-a-datasource)
  - [Add a datasink](#add-a-datasink)
  - [Add an application](#add-an-application)
  - [Adding log collection (telemetry)](#adding-log-collection-telemetry)
  - [Add secret store](#add-secret-store)
  - [Add identity](#add-identity)
- [See the configuration file](#see-the-configuration-file)
- [Export configuration for sharing](#export-configuration-for-sharing)
- [Consolidating the configuration across collaborators](#consolidating-the-configuration-across-collaborators)

# Overview
This page shows how to configure a cleanroom to access multiple resources from different collaborators by using configuration files. After your data sources, datasinks and applications are defined in one or more configuration files, you can then consolidate the same and use the consolidated specification to agree upon the final shape of the clean room environment and drive its creation.

# Define datasources, datasinks and applications
Suppose we have 2 collaborators named `publisher` and `consumer` where the publisher wants to configure both a datasource and datasink while the consumer wants to specify the application to run. Exposing a datasource requires encrypting and uploading files into a storage account. Creating a datasink requires preparing keys used for encrypting output files generated during the clean room execution. Running an application requires specifying the image location, command and any env variables.

Create a directory named `publisher-demo`. In your `publisher-demo` directory, create a file named `publisher-config` with this content:
```yaml
identities:
specification:
  dataSources:
  dataSinks:
  applications:
  telemetry:
```
A configuration file describes the various data stores, data sinks, applications etc. that will be used in a clean room environemnt.

## Add a datasource
Go to your `publisher-demo` directory. Enter these commands to add datastore details to your configuration file:
```powershell
az cleanroom config set-datasource `
    --cleanroom-config publisher-config `
    --name development `
    --storage-account <> `
    --identity <> `
    --key-vault <>
```
Run below command to upload the files from a local folder with encryption in the above datastore so that it can be made available to the clean room during its execution:
```powershell
az cleanroom datasource upload
    --cleanroom-config publisher-config`
    --name development
    --dataset-folder <>
```

## Add a datasink
Go to your `publisher-demo` directory. Enter these commands to add datasink details to your configuration file:
```powershell
az cleanroom config set-datasink `
    --cleanroom-config publisher-config `
    --name development-output `
    --storage-account <> `
    --identity <> `
    --key-vault <>
```
Once clean room execution completes run below command to download and decrypt files to a local folder from the above datasink:
```powershell
az cleanroom datasink download
    --cleanroom-config publisher-config`
    --name development-output
```

## Add an application
Create a directory named `consumer-demo`. In your `consumer-demo` directory, create a file named `consumer-config` with this content:
```yaml
identities:
specification:
  dataSources:
  dataSinks:
  applications:
  telemetry:
```

Go to your `consumer-demo` directory. Enter these commands to add application details to your configuration file:
```powershell
az cleanroom config set-application `
    --cleanroom-config consumer-config `
    --name model-training `
    --image ghcr.io/model@sha256 `
    --command "/bin/bash run.sh" `
    --mount "src=development,dst=/mnt/remote/development"
    --mount "src=development-output,dst=/mnt/remote/output"
    --env-var "model_config":"/mnt/remote/development/model_config.json" `
    --env-var "query_config":"/mnt/remote/dvelopment/query_config.json"
```

## Adding log collection (telemetry)
Go to your `publisher-demo` directory. Enter these commands to add telemetry/log collection details to your configuration file:
```powershell
az cleanroom config set-telemetry `
    --cleanroom-config publisher-config `
    --storage-account <> `
    --identity <> `
    --key-vault <>
```
Once clean room execution completes run below command to download and decrypt the log files to a local folder:
```powershell
az cleanroom telemetry download
    --cleanroom-config publisher-config
```

## Add secret store
```powershell
az cleanroom config set-secretstore `
    --cleanroom-config publisher-config `
```

## Add identity
```powershell
az cleanroom config set-identity `
    --cleanroom-config publisher-config `
```

# See the configuration file
```powershell
az cleanroom config show --cleanroom-config publisher-config
```
The output shows the datasource, datasink details that have been configured.
```yaml
identities:
specification:
  dataSources:
  - name: development
    datastore:
      identity: ...
      keystore: ...
  dataSinks:
  - name: development-output
    datasink:
      identity: ...
      keystore: ...
  applications:
  telemetry:
```

```powershell
az cleanroom config show --cleanroom-config consumer-config
```
The output shows the application details that have been configured.
```yaml
identities:
specification:
  dataSources:
  dataSinks:
  applications:
  - name: model-training
    application:
      image: ...
      command: ...
      mounts:
      - name: development
        mountPath: /mnt/remote/development
      - name: development-output
        mountPath: /mnt/remote/output
  telemetry:
```

# Export configuration for sharing
Go to your `publisher-demo` directory. Run the below command to export the configuration file that can be shared with other collaborators. The below command removes an private information that is not meant for sharing (eg path to the encryption keys).
```powershell
az cleanroom config export --cleanroom-config publisher-config > publisher-config-public
```

# Consolidating the configuration across collaborators
The final clean room specification that can be used for clean room deployment is a union of the clean room specs taken from each of the collaborators. To create the merged spec from all the configuration files run the following commands.

```powershell
# Export publisher config
az cleanroom config export --cleanroom-config publisher-config > publisher-config-public

# Export consumer config
az cleanroom config export --cleanroom-config consumer-config > consumer-config-public

# Merge the two configs
az cleanroom config view --cleanroom-config consumer-config-public publisher-config-public
```
The output shows merged information from all the files listed passed into the `view` command. In particular, notice that the merged information has the `datasource/datasink` entries from the publisher-config-public and the `application` entry from the consumer-config-public file.
```yaml
specification:
  dataSources:
  - name: development
    datastore:
      identity: ...
      keystore: ...
  dataSinks:
  - name: development-output
    datasink:
      identity: ...
      keystore: ...
  applications:
  - name: model-training
    application:
      image: ...
      command: ...
  telemetry:
```