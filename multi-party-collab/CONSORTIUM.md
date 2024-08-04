# Setting up a consortium for multi-party collaboration <!-- omit from toc -->

- [1. Preparing samples environment inside a docker container](#1-preparing-samples-environment-inside-a-docker-container)
  - [1.1. Prerequisites](#11-prerequisites)
  - [1.2. Generating the docker image](#12-generating-the-docker-image)
  - [1.3. Bringing up the environment](#13-bringing-up-the-environment)
- [4. High level execution sequence](#4-high-level-execution-sequence)
- [5. Setup the consortium](#5-setup-the-consortium)
  - [5.1. Member identity creation](#51-member-identity-creation)
  - [5.2. Creating the consortium](#52-creating-the-consortium)
- [6. Publisher: Preparing encrypted datasets](#6-publisher-preparing-encrypted-datasets)
  - [6.1. KEK-DEK based encryption approach](#61-kek-dek-based-encryption-approach)
  - [6.2. Encrypt and upload data](#62-encrypt-and-upload-data)
- [7. Publisher: Setting up log collection](#7-publisher-setting-up-log-collection)
- [8. Share publisher clean room configuration with consumer](#8-share-publisher-clean-room-configuration-with-consumer)
- [9. Consumer: Output preparation and application configuration](#9-consumer-output-preparation-and-application-configuration)
  - [9.1. Preparing datasink to receive output](#91-preparing-datasink-to-receive-output)
  - [9.2. Application configuration and mount points](#92-application-configuration-and-mount-points)
    - [9.2.1. Mounting storage containers using Blobfuse2](#921-mounting-storage-containers-using-blobfuse2)
- [10. Proposing a governance contract](#10-proposing-a-governance-contract)
- [11. Agreeing upon the contract](#11-agreeing-upon-the-contract)
  - [11.1. Agree as publisher](#111-agree-as-publisher)
  - [11.2. Agree as consumer](#112-agree-as-consumer)
- [12. Propose ARM template, CCE policy and log collection](#12-propose-arm-template-cce-policy-and-log-collection)
- [13. Accept ARM template, CCE policy and logging proposals](#13-accept-arm-template-cce-policy-and-logging-proposals)
  - [13.1. Verify and accept as publisher](#131-verify-and-accept-as-publisher)
  - [13.2. Verify and accept as consumer](#132-verify-and-accept-as-consumer)
- [14. Setup access for the clean room](#14-setup-access-for-the-clean-room)
  - [14.1. Setup access as publisher](#141-setup-access-as-publisher)
  - [14.2. Setup access as consumer](#142-setup-access-as-consumer)
- [15. Deploy clean room](#15-deploy-clean-room)
- [16. Download encrypted output](#16-download-encrypted-output)
- [17. Download and share logs](#17-download-and-share-logs)
  - [17.1. Explore the downloaded logs](#171-explore-the-downloaded-logs)
  - [17.2. View telemetry for infrastucture containers](#172-view-telemetry-for-infrastucture-containers)
  - [17.3. See audit events](#173-see-audit-events)
- [18. Next Steps](#18-next-steps)


# 1. Preparing samples environment inside a docker container
## 1.1. Prerequisites
To set this infrastructure up, we will need the following tools to be installed prior to running the samples.
1. An Azure subscription with adequate permissions to create resources and manage permissions on these resources.
2. Docker installed locally. Installation instructions [here](https://docs.docker.com/engine/install/).

## 1.2. Generating the docker image
```powershell
docker image build -t azure-cleanroom-samples -f ./docker/Dockerfile.multi-party-collab "."
```

## 1.3. Bringing up the environment

<details>
<summary>Click to expand</summary>

This is the content of the collapsible section. You can include any Markdown-formatted text, lists, or code here.

</details>

# 4. High level execution sequence
Before we begin below gives the overall flow of execution that happens in this sample. It gives a high level perspective that might be helpful to keep in mind as you run thru the steps.
```mermaid
sequenceDiagram
    title Overall flow
    participant m1 as Publisher
    participant m0 as Consumer
    participant CCF as Clean Room Governance<br>(CCF instance)
    participant CACI as Clean Room<br> (CACI instance)

    m0->>CCF: Creates consortium
    m1->>CCF: Joins consortium
    m1->>m1: Prepares datasets
    m1->>m1: Setup log collection
    m0->>m0: Prepares application and datasets
    m0->>CCF: Proposes clean room contract
    m1->>CCF: Accepts contract
    m0->>CCF: Proposes ARM deployment<br> template and CCE policy
    m0->>CCF: Proposes enable logging
    m1->>CCF: Accepts ARM deployment<br> template and CCE policy
    m1->>CCF: Accepts enable logging
    m0->>m0: Configure access to resources by clean room
    m1->>m1: Configures access to resources by clean room
    m0->>CACI: Deploys clean room
    CACI->>CCF: Check execution consent
    CACI->>CCF: Get tokens for Azure resource access
    CACI->>CACI: Access secrets in Key Vault
    CACI->>CACI: Access encrypted storage
    CACI->>CACI: Write out result to encrypted storage
    m0->>CACI: Waits for result
    m1->>m0: Shares application logs
```

Once the clean room is deployed the key components involved during execution are shown below:

![alt text](./assets/encrypted-storage-layout.png)

> [!NOTE]
> The steps henceforth assume that you are working in the `/home/samples` directory and all commands are executed relative to that.

# 5. Setup the consortium
This collaboration between the publishers and the consumers is realized by creating a [consortium in CCF](https://microsoft.github.io/CCF/main/overview/what_is_ccf.html) which runs a [clean room governance service](../../src/governance/README.md) where all the parties become participating members. Each CCF consortium member is identified by a public-key certificate used for client authentication and command signing. So first, the identity public and private key pairs for the members need be created.

## 5.1. Member identity creation
```powershell
# Ensure you have openssl installed before running the command below.
az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $env:CUSTOMERNAME --out ./demo-resources.private
```
Above command shows output similar to below.
```powershell
-- Generating identity private key and certificate for participant "contosso"...
Identity curve: secp384r1
Identity private key generated at:   ./demo-resources.private/contosso_privk.pem
Identity certificate generated at:   ./demo-resources.private/contosso_cert.pem (to be registered in CCF)
-- Generating RSA encryption key pair for participant "contosso"...
writing RSA key
Encryption private key generated at:  ./demo-resources.private/contosso_enc_privk.pem
Encryption public key generated at:   ./demo-resources.private/contosso_enc_pubk.pem (to be registered in CCF)
```
The above command will generate the public/private key pair. The member’s identity private key should be stored on a trusted device (e.g. HSM) and kept private (not shared with any other member) while the certificate (e.g. member_name_cert.pem) would be registered in CCF (later in the flow).

## 5.2. Creating the consortium
As the next step a CCF instance needs to be created with the above members. From a confidentiality perspective any of the members (or a 3rd party like an ISV) can create the CCF instance without affecting the zero-trust assurances. In this sample we assume that between the publisher and the consumer it was agreed upon that the consumer will host the CCF instance. The consumer would create the CCF instance and then invite the publisher as a member into the consortium.

```mermaid
sequenceDiagram
    title Creating the consortium with members
    participant m1 as Publisher
    participant m0 as Consumer
    participant CCF as CCF instance

    m0->>CCF: Create mCCF instance
    CCF-->>m0: CCF created
    m0->>CCF: Activate membership
    Note over CCF: Consumer active
    m0->>CCF: Deploy governance service
    CCF-->>m0: State: Service deployed
    m1->>m0: Share publisher identity cert
    m0->>CCF: Propose adding publisher as member
    CCF-->>m0: Proposal ID
    m0->>CCF: Vote for Proposal ID
    CCF-->>m0: State: Accepted
    Note over CCF: Publisher accepted
    m0->>m1: Share ccfEndpoint URL eg.<br>https://<name>.confidential-ledger.azure.com
    m1->>CCF: Verifies state of the consortium
    m1->>CCF: Activate membership
    Note over CCF: Publisher active
```

### 5.2.1. Create the CCF instance <!-- omit from toc -->
First ensure that you are logged into Azure and set the subscription (if required).
```powershell
# Login to Azure.
az login

# Set active subscription (optional).
az account set --subscription "<subname>"
```
Run the below steps to create the CCF instance.
```powershell
az group create --name $env:RESOURCEGROUP --location westus

# Create the mCCF instance.
$ccfName = $env:RESOURCEGROUP + "-ccf"
$consumerCert = "./demo-resources/"+ $env:CUSTOMERNAME +"_cert.pem" # Created previously via the keygenerator-sh command.
az confidentialledger managedccfs create `
    --name $ccfName `
    --resource-group $env:RESOURCEGROUP `
    --location "southcentralus" `
    --members "[{certificate:'$consumerCert',identifier:'$env:CUSTOMERNAME'}]"

$ccfEndpoint = (az confidentialledger managedccfs show `
    --resource-group $env:RESOURCEGROUP `
    --name $ccfName `
    --query "properties.appUri" `
    --output tsv)

# "consumer" deploys client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert ./demo-resources.private/$($env:CUSTOMERNAME)_cert.pem `
  --signing-key ./demo-resources.private/$($env:CUSTOMERNAME)_privk.pem `
  --name "$env:CUSTOMERNAME-client"

# Activate membership.
az cleanroom governance member activate --governance-client "$env:CUSTOMERNAME-client"

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client "$env:CUSTOMERNAME-client"

# Set tenant Id as a part of the member data. This is required to enable OIDC provider in the later steps.
$consumerTenantId = az account show --query "tenantId" --output tsv
$proposalId = (az cleanroom governance member set-tenant-id `
  --identifier consumer `
  --tenant-id $consumerTenantId `
  --query "proposalId" `
  --output tsv `
  --governance-client "$env:CUSTOMERNAME-client")

az cleanroom governance proposal vote `
  --proposal-id $proposalId `
  --action accept `
  --governance-client "consumer-client"
```

### 5.2.2. Invite members into the consortium <!-- omit from toc -->
Once the CCF instance is created with the consumer as the initial member the next step is to add the publisher into the consortium. For this the publisher needs to share their identity public key (`publisher_cert.pem`) and the Tenant Id with the consumer and then the consumer (who is hosting the CCF instance) needs to run the below command:
```powershell
# In this demo both consumer and publisher are running in the same tenant. If publisher is coming from different Microsoft Entra ID tenant then use that value below.
$publisherTenantId = az account show --query "tenantId" --output tsv

# "consumer" member makes a proposal for adding the new member "publisher".
$proposalId = (az cleanroom governance member add `
    --certificate ./demo-resources.public/publisher_cert.pem `
    --identifier "publisher" `
    --tenant-id $publisherTenantId `
    --query "proposalId" `
    --output tsv `
    --governance-client "$env:CUSTOMERNAME-client")

# Vote on the above proposal to accept the membership.
az cleanroom governance proposal vote `
  --proposal-id $proposalId `
  --action accept `
  --governance-client "$env:CUSTOMERNAME-client"
```

Once the consumer has added the publisher as the member the publisher now needs to activate their membership before they can participate in the collaboration. The consumer must share the `ccfEndpoint` value to the publisher so they can know which CCF instance to connect to.

```powershell
# "publisher" deploys client-side containers to interact with the governance service as the new member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert ./demo-resources.private/$($env:CUSTOMERNAME)_cert.pem `
  --signing-key ./demo-resources.private/$($env:CUSTOMERNAME)_privk.pem `
  --name "$env:CUSTOMERNAME-client"

# "publisher" accepts the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client "$env:CUSTOMERNAME-client"
```
With the above steps the consortium creation that drives the creation and execution of the clean room is complete. We now proceed to preparing the datasets and making them available in the clean room.

# 6. Publisher: Preparing encrypted datasets
## 6.1. KEK-DEK based encryption approach
The datasets that the publisher/consumer want to bring into the collaboration would be encrypted by the respective parties such that the key to decrypt the same will only be released to the clean room environment. The sample follows an envelope encryption model for encryption of data. For the encryption of the datasets *Data Encryption Keys* (DEK) are generated, which are symmetric in nature. An asymmetric key, called *the Key Encryption Key* (KEK), is generated subsequently to wrap the DEK. The wrapped DEKs are stored in a Key Vault as a secret and the KEK is imported into an MHSM/Premium Key Vault behind a secure key release (SKR) policy. Within the clean room, the wrapped DEK is read from the Key Vault and the KEK is retrieved from the MHSM/Premium Key Vault following the [secure key release](https://learn.microsoft.com/en-us/azure/confidential-computing/concept-skr-attestation) protocol. The DEKs are unwrapped within the cleanroom and then used to access the storage containers.

The parties can choose between a Managed HSM or a Premium Azure Key Vault for storing their encryption keys passing the `-kvType` paramter to the scripts below.

## 6.2. Encrypt and upload data
It is assumed that the publisher has had out-of-band communication with the consumer and have agreed on the data sets that will be shared. In this sample it assumes that the dataset(s) are in the form of one or more files in one or more folders at the publisher's end.

The setup involves creating an Azure resource group into which a storage account and a Managed HSM or Premium Key Vault are deployed. The dataset(s) in the form of files are encrypted (using the KEK-DEK approach mentioned earlier) and uploaded into the the storage account. Each folder in the source dataset would correspond to one storage container, and all files in that folder are [uploaded as blobs to Azure Storage using Customer Provided Keys](https://learn.microsoft.com/azure/storage/blobs/encryption-customer-provided-keys). The sample creates one symmetric key per folder (storage container).

```mermaid
sequenceDiagram
    title Encrypting and uploading data to Azure Storage
    participant m1 as Publisher
    participant storage as Azure Storage
    participant akv as Azure Key Vault
    participant mi as Managed Identity

    m1->>akv: Create Key Vault
    Note over m1: Key Vault will be used later <br>to save the wrapped DEKs
    m1->>mi: Create Managed Identity
    Note over m1: Managed identity will be configured later <br>to give clean room access to the key vault
    loop every dataset folder
        m1->>m1: Generate symmetric key (DEK) per folder
        m1->>storage: Create storage container for folder
        loop every file in folder
            m1->>storage: Encrypt file using DEK and upload to container
        end
    end
```
In your `publisher-demo` directory in this sample, initialize a clean room configuration file named `publisher-config` with the below command:
```powershell
$publisherConfig = "./publisher-demo/publisher-config"
az cleanroom config init --cleanroom-config $publisherConfig
```
The above command creates the file with the below content:
```
identities: []
specification:
  applications: []
  datasinks: []
  datasources: []
  telemetry: {}

```

In the `publisher-demo` directory enter the below to create a storage account, add the dataset `publisher-input` as a datasource and then encrypt and upload files into Azure storage. If your scenario has multiple datasets/folders that need to be encrypted and uploaded then repeat the `add-datasource` and `upload` commands for every folder.
```powershell
$publisherResourceGroup = "publisher-$((New-Guid).ToString().Substring(0, 8))"

# Create storage account, KV and MI resources.
$result = (./prepare-resources.ps1 -resourceGroup $publisherResourceGroup -kvType akvpremium)

# Create a KEK entry in the configuration.
az cleanroom config set-kek `
    --kek-key-vault $result.kek.kv.id `
    --maa-url $result.maa_endpoint `
    --cleanroom-config $publisherConfig

# Create a datasource entry in the configuration.
az cleanroom config add-datasource `
    --cleanroom-config $publisherConfig `
    --name publisher-input `
    --storage-account $result.sa.id `
    --identity $result.mi.id `
    --dek-key-vault $result.dek.kv.id

# Encrypt and upload content.
az cleanroom datasource upload `
    --cleanroom-config $publisherConfig `
    --name publisher-input `
    --dataset-folder ./publisher-demo/publisher-input
```

The above steps captures the information related to the datasets provided, their URLs in the storage accounts and encryption key information in the `publisher-config` file. This file would be exported later and shared with the consumer to let them know the datsources the publisher is sharing via the clean room.

> [!TIP]
> `add-datasource` step might fail with the below error in case the RBAC permissions on the storage account created by the `prepare-resources.ps1` has not been applied yet. Try the `add-datasource` command again after a while.
> 
> ![alt text](./assets/add-datasource-error.png)

# 7. Publisher: Setting up log collection
In this collabration say the consumer wants to inspect both the infrastructure and application logs once clean room finishes execution. But the publisher has a concern that sensitive information might leak out via logs and hence wants to inspect the log files before the consumer gets them. This can be achieved by using a storage account that is under the control of the publisher as the destination for the execution logs. These log files will be encrypted and written out to Azure storage with a key that is in the publisher's control. The publisher can then download and decrypt these logs, inspect them and if satisfied can share these with the consumer.

The below step configures the storage account endpoint details for collecting the application logs. Actual download of the logs happens later on.
```powershell
# $result below refers to the output of the prepare-resources.ps1 that was run earlier.
az cleanroom config set-logging `
    --cleanroom-config $publisherConfig `
    --storage-account $result.sa.id `
    --identity $result.mi.id `
    --dek-key-vault $result.dek.kv.id

az cleanroom config set-telemetry `
    --cleanroom-config $publisherConfig `
    --storage-account $result.sa.id `
    --identity $result.mi.id `
    --dek-key-vault $result.dek.kv.id
```

# 8. Share publisher clean room configuration with consumer
For the consumer to configure their application to access the data from the publisher it needs to know the details about the datasources that have been prepared by the publisher. Eg the consumer needs to refer to the individual datasources by their name when specifying where to mount each datasource in the container. The publisher needs to share the `publisher-config` file with the consumer.

# 9. Consumer: Output preparation and application configuration
## 9.1. Preparing datasink to receive output
In your `consumer-demo` directory in this sample, initialize a clean room configuration file named `consumer-config` with the below command:
```powershell
$consumerConfig = "./consumer-demo/consumer-config"
az cleanroom config init --cleanroom-config $consumerConfig
```
The above command creates the file with the below content:
```
identities: []
specification:
  applications: []
  datasinks: []
  datasources: []
  telemetry: {}
```
In the `consumer-demo` directory enter the below to prepare a datasink that will receive the encrypted output that is generated by the clean room and is meant for the consumer's consumption:
```powershell
$consumerResourceGroup = "consumer-$((New-Guid).ToString().Substring(0, 8))"

# Create storage account, KV and MI resources.
$result = (./prepare-resources.ps1 -resourceGroup $consumerResourceGroup -kvType akvpremium)

# Create a KEK entry in the configuration.
az cleanroom config set-kek `
    --kek-key-vault $result.kek.kv.id `
    --maa-url $result.maa_endpoint `
    --cleanroom-config $consumerConfig

# Create a datasink entry in the configuration.
az cleanroom config add-datasink `
    --cleanroom-config $consumerConfig `
    --name consumer-output `
    --storage-account $result.sa.id `
    --identity $result.mi.id `
    --dek-key-vault $result.dek.kv.id
```

The above steps prepares a storage account to receive the clean room output and captures the information related to the output like the storage account and encryption key information in the `consumer-config` file.

## 9.2. Application configuration and mount points
The application details such as the app name, container registry, image ID, command, environment variables and resources needs to be captured as below. Replace the values for the parameters as appropriate.

The sample application is located at `consumer-demo/application` directory. It is a `golang` application that reads a text file from `INPUT_LOCATION`, compresses it and writes the archive out to `OUTPUT_LOCATION`. The below command adds the application details to the configuration file.
```powershell
$sample_code = $(cat ./consumer-demo/application/main.go | base64 -w 0)
az cleanroom config add-application `
    --cleanroom-config $consumerConfig `
    --name demo-app `
    --image "docker.io/golang@sha256:f43c6f049f04cbbaeb28f0aad3eea15274a7d0a7899a617d0037aec48d7ab010" `
    --command "bash -c 'echo `$CODE | base64 -d > main.go; go run main.go'" `
    --mounts "src=publisher-input,dst=/mnt/remote/input" `
             "src=consumer-output,dst=/mnt/remote/output" `
    --env-vars OUTPUT_LOCATION=/mnt/remote/output `
               INPUT_LOCATION=/mnt/remote/input `
               CODE="$sample_code" `
    --cpu 0.5 `
    --memory 4
```
For demo purposes this sample uses the `golang` container image to compile and run code from within the container image itself. In a real world scenario the container image would be the consumer's application and not the `golang` image.

### 9.2.1. Mounting storage containers using Blobfuse2
The `--mounts` flag allows you to mount a datasource or datasink in a container. `--mount` consists of multiple key-value pairs, separated by commas and each consisting of a `key=value` tuple.
- `src`: The source of the mount. This is the `name` of a `datasource` or `datasink` that needs to be mounted. Eg in this sample `publisher-input` is the datasource name present in `publisher-config` while `consumer-output` is the datasink name present in `consumer-config`.
- `dst`: The destination takes as its value the path where the datasource/datasink gets mounted in the container.

During clean room execution each of the `src` mounts that are mentioned above get exposed transparently as file system mount points using [Azure Storage Blosefuse2](https://github.com/Azure/azure-storage-fuse/tree/main?tab=readme-ov-file#about) driver. The application container reads clear text data and writes clear text data to/from the `src` mountpoint(s) and does not need to deal with any encryption/decryption semantics. The blob fuse driver transparently decrypts (for application reads) and encrypts (for application writes) using the [DEK](#61-kek-dek-based-encryption-approach) that gets released during clean room execution.

The resources for the application container should be allocated so as not to violate confidential ACI limits as defined [here](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-resource-and-quota-limits#confidential-container-resources-preview).

# 10. Proposing a governance contract
Once the two parties are finished with above steps we have the following artifacts generated:
- `publisher-config` document at the publisher's end and shared with the consumer.
- `consumer-config` document at the consumer's end

The above documents captures various details that both parties need to exchange and agree upon before the clean room can be created and deployed. This exchange and agreement is captured formally by creation of a *governance contract* hosted in CCF which would contain the *clean room specification*. The clean room specification is a YAML document that is generated using these two documents and captures the collaboration details in a [formal specification](../../docs/cleanroomspec.md).

The contract creation and proposal can be initiated by either of the 2 parties without affecting zero-trust assurances. In our sample we assume the consumer takes the responsibility of making the proposal.

```mermaid
sequenceDiagram
    title Proposing and agreeing upon a governance contract
    participant m1 as Publisher
    participant m0 as Consumer
    participant CCF as CCF instance

    m1->>m0: Shares publisher-config
    m0->>CCF: Create governance contract from <br>publisher-config, consumer-config
    CCF-->>m0: State: Contract created
    m0->>CCF: Propose contract
    CCF-->>m0: Proposal ID
    m0->>CCF: Get proposal ID details
    m0->>m0: Verify contract proposal details
    m0->>CCF: Vote acceptance for Proposal ID
    CCF-->>m0: State: Contract proposed
    m0->>m1: Shares proposal ID
    m1->>CCF: Get proposal ID details
    m1->>m1: Verify contract proposal details
    m1->>CCF: Vote acceptance for Proposal ID
    CCF-->>m1: State: Contract Accepted
```

The above sequence of steps are performed by the commands below:
```powershell
# Generate the cleanroom config which contains all the datasources, sinks and applications that are
# configured by both the producer and consumer.
az cleanroom config view `
    --cleanroom-config $consumerConfig `
    --configs $publisherConfig > ./demo-resources/cleanroom-config

# Validate the contract structure before proposing.
az cleanroom config validate --cleanroom-config ./demo-resources/cleanroom-config

$contractId = "collab1" # A unique identifier to refer to this collaboration.
$data = Get-Content -Raw ./demo-resources/cleanroom-config
az cleanroom governance contract create `
    --data "$data" `
    --id $contractId `
    --governance-client "consumer-client"

# Submitting a contract proposal.
$version = (az cleanroom governance contract show `
    --id $contractId `
    --query "version" `
    --output tsv `
    --governance-client "consumer-client")

az cleanroom governance contract propose `
    --version $version `
    --id $contractId `
    --query "proposalId" `
    --output tsv `
    --governance-client "consumer-client"
```
The above command creates a contract in the governance service with the clean room specification yaml as its contents. Next both the consumer and publisher inspect the proposed contract and accept after verification.

# 11. Agreeing upon the contract
The publisher/client can now query CCF to get the proposed contract, run their validations and accept or reject the contract. To achieve this:

## 11.1. Agree as publisher 
```powershell
$contract = (az cleanroom governance contract show `
    --id $contractId `
    --governance-client "publisher-client" | ConvertFrom-Json)

# Inspect the contract details that is capturing the storage, application container and identity details.
$contract.data

# Accept it.
az cleanroom governance contract vote `
    --id $contractId `
    --proposal-id $contract.proposalId `
    --action accept `
    --governance-client "publisher-client"
```
## 11.2. Agree as consumer
```powershell
$contract = (az cleanroom governance contract show `
    --id $contractId `
    --governance-client "consumer-client" | ConvertFrom-Json)

# Inspect the contract details that is capturing the storage, application container and identity details.
$contract.data

# Accept it.
az cleanroom governance contract vote `
    --id $contractId `
    --proposal-id $contract.proposalId `
    --action accept `
    --governance-client "consumer-client"
```

# 12. Propose ARM template, CCE policy and log collection
Once the contract is accepted by both parties, the party deploying the clean room can now generate an [Azure Confidential Container Instance](https://learn.microsoft.com/azure/container-instances/container-instances-confidential-overview) ARM template along with the CCE policy. Once the ARM template is generated, the [Confidential Computing Enforcement (CCE) policy](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-confidential-overview#confidential-computing-enforcement-policies) can be computed. The command below generates both the ARM template and CCE policy following the flow mentioned [here](https://learn.microsoft.com/azure/container-instances/container-instances-tutorial-deploy-confidential-containers-cce-arm). Run the following command:
```powershell
az cleanroom governance deployment generate `
    --contract-id $contractId `
    --governance-client "consumer-client" `
    --output-dir ./demo-resources
```
> [!NOTE]
> The above command invokes `az confcom acipolicygen` and takes around 10-15 minutes to finish.

Once run, this creates the following files in the output directory specified above: 
 1. `cleanroom-arm-template.json`. This is the ARM template that can be deployed. This has the base64 encoded CCE policy embedded in it.
 2. `cleanroom-governance-policy.json`. This file contains the clean room policy which identifies this clean room when its under execution.

Now propose the template and policy along with also submitting a proposal for enabling log collection.

```powershell
az cleanroom governance deployment template propose `
    --template-file ./demo-resources/cleanroom-arm-template.json `
    --contract-id $contractId `
    --governance-client "consumer-client"

az cleanroom governance deployment policy propose `
    --policy-file ./demo-resources/cleanroom-governance-policy.json `
    --contract-id $contractId `
    --governance-client "consumer-client"

# Propose enabling log and telemetry collection during cleanroom execution.
az cleanroom governance contract runtime-option propose `
    --option logging `
    --action enable `
    --contract-id $contractId `
    --governance-client "consumer-client"

az cleanroom governance contract runtime-option propose `
    --option telemetry `
    --action enable `
    --contract-id $contractId `
    --governance-client "consumer-client"
```

The generated ARM template and CCE policy are raised as proposals in the governance service on the same contract that was accepted. The proposals can be inspected as follows:
```powershell
# Inspect the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client "consumer-client" `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args.spec.data" `
    --governance-client "consumer-client"

# Inspect the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client "consumer-client" `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args" `
    --governance-client "consumer-client"
```

# 13. Accept ARM template, CCE policy and logging proposals
Once the ARM template and CCE policy proposals are available, the remaining parties can validate and vote on these proposals. In this sample, we run a simple validation and accept the template and CCE policy.

## 13.1. Verify and accept as publisher
Run the following as the publisher.
```powershell
$clientName = "publisher-client"
./verify-deployment-proposals.ps1 `
    -cleanroomConfig $publisherConfig `
    -governanceClient $clientName

# Vote on the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the enable logging proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option logging `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the enable telemetry proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option telemetry `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName
```

## 13.2. Verify and accept as consumer
Run the following as the consumer.
```powershell
$clientName = "consumer-client"
./verify-deployment-proposals.ps1 `
    -cleanroomConfig $consumerConfig `
    -governanceClient $clientName

# Vote on the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the enable logging proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option logging `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName

# Vote on the enable telemetry proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option telemetry `
    --contract-id $contractId `
    --governance-client $clientName `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $clientName
```

# 14. Setup access for the clean room
Both the publisher and the consumer need to give access to the clean room so that the clean room environment can access resources in their respective tenants. To do this first the the DEKs that were created for dataset encryption are now wrapped using a KEK. The KEK is uploaded in Key Vault and configured with a secure key release (SKR) policy while the wrapped-DEK is saved as a secret in Key Vault.

Further the managed identities (created earlier as part of the dataset preparation) is given access to resources and then we create federated credentials on the managed identity. The federated credential allows the clean room to get the managed identity access token during execution.

The flow below is executed by both the publisher and the consumer in their respective Azure tenants.

```mermaid
sequenceDiagram
    title Clean room access setup
    participant m0 as Publisher/Consumer
    participant akv as Azure Key Vault
    participant storage as Azure Storage
    participant mi as ManagedIdentity

    m0->>m0: Create KEK
    loop every DEK
        m0->>m0: Wrap DEK with KEK
        m0->>akv: Save wrapped-DEK as secret
    end
    m0->>akv: Save KEK with SKR policy
    m0->>storage: Assign storage account permissions to MI
    m0->>akv: Assign KV permissions to MI
    m0->>m0: Setup OIDC issuer endpoint
    m0->>mi: Setup federated credential on MI
```
## 14.1. Setup access as publisher
Run the following as the publisher.
```powershell
# Creates a KEK with SKR policy, wraps DEKs with the KEK and put in kv.
az cleanroom config wrap-deks `
    --contract-id $contractId `
    --cleanroom-config $publisherConfig `
    --governance-client "publisher-client"

# Setup OIDC issuer and managed identity access to storage/KV in publisher tenant.
./setup-access.ps1 `
    -resourceGroup $publisherResourceGroup `
    -contractId $contractId  `
    -governanceClient "publisher-client"
```
> [!TIP]
> `setup-access` step might fail with the below error in case the RBAC permissions on the storage account created by the it has not been applied yet by the time its attempting to create a storage account. Try the command again after a while.
> 
> ![alt text](./assets/setup-access-error.png)

## 14.2. Setup access as consumer
Run the following as the consumer.
```powershell
# Creates a KEK with SKR policy, wraps DEKs with the KEK and put in kv.
az cleanroom config wrap-deks `
    --contract-id $contractId `
    --cleanroom-config $consumerConfig `
    --governance-client "consumer-client"

# Setup OIDC issuer endpoint and managed identity access to storage/KV in consumer tenant.
./setup-access.ps1 `
    -resourceGroup $consumerResourceGroup `
    -contractId $contractId `
    -governanceClient "consumer-client"
```

# 15. Deploy clean room
Once the ARM template and CCE policy proposals have been accepted and access has been configured, the party deploying the clean room (the consumer in our case) can do so by running the following:

```powershell
# Get the agreed upon ARM template for deployment.
(az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client "consumer-client" `
    --query "data") | Out-File "./demo-resources/aci-deployment-template.json"

# Deploy the clean room.
$cleanRoomName = "collab-cleanroom"
az deployment group create `
    --resource-group $consumerResourceGroup `
    --name $cleanRoomName `
    --template-file "./demo-resources/aci-deployment-template.json"
```
Run the following script to wait for the cleanroom to exit.
```powershell
./wait-for-cleanroom.ps1 -cleanRoomName $cleanRoomName -resourceGroup $consumerResourceGroup
```

Once execution completes the result is written out to `consumer-ouput` datasink as configured by the consumer.

# 16. Download encrypted output
Post execution, the encrypted output is written out to the consumer's storage account. To decrypt and download this, run the following:
```powershell
az cleanroom datasink download `
    --cleanroom-config $consumerConfig `
    --name consumer-output `
    --target-folder "./consumer-demo/consumer-output"
```
This downloads the files from the storage container into the specified folder. There should be an `output.gz` file in the `consumer-demo/consumer-output` folder. Decompress the same via the below command and compare the contents of the decompressed file with that of `publisher-demo/publisher-input/input.txt`:
```powershell
gzip -d ./consumer-demo/consumer-output/consumer-output/output.gz
cat ./consumer-demo/consumer-output/consumer-output/output
```

# 17. Download and share logs
The publisher can download the infrastructure telemetry and application logs. These are available post execution in an encrypted form. To decrypt and inspect, run the following:
```powershell
az cleanroom logs download `
    --cleanroom-config $publisherConfig `
    --target-folder "./publisher-demo/logs"

az cleanroom telemetry download `
    --cleanroom-config $publisherConfig `
    --target-folder "./publisher-demo/telemetry"
```
The above command will download into the specified target folder and decrypt the various files for metrics, traces and logs. The publisher can inspect these files and then choose to share them with the consumer.

## 17.1. Explore the downloaded logs
See the logs emitted by the application container using the below command:
```powershell
cat ./publisher-demo/logs/application-telemetry/demo-app.log
```
This shows output as below:
```powershell
2024-06-05T12:54:17.945694635+00:00 stdout F File is present at: /mnt/remote/input/input.txt
2024-06-05T12:54:17.945694635+00:00 stdout F Opening the input file.
2024-06-05T12:54:17.953695222+00:00 stdout F Creating the output file.
2024-06-05T12:54:18.168096107+00:00 stdout F Compressing the file.
2024-06-05T12:54:18.169313592+00:00 stdout F File compressed successfully.
```
## 17.2. View telemetry for infrastucture containers

You can also inspect the telemetry emitted by the clean room infrastructure containers as telemetry was enabled in this sample.

The infrastructure containers traces, logs and metrics that are useful for debugging errors, tracing the execution sequence etc.

To view the telemetry, run the following command:

```powershell
az cleanroom telemetry aspire-dashboard `
    --telemetry-folder ./publisher-demo/telemetry/infrastructure-telemetry
```

The telemetry dashboard uses [.NET Aspire Dashboard](https://learn.microsoft.com/en-us/dotnet/aspire/fundamentals/dashboard/standalone?tabs=bash) to display the traces, logs and metrics that are generated. This spins up a set of docker containers with the aspire dashboard to visualize the telemetry.

There are different views that are available:
1. Traces: Track requests and activities across all the sidecars so that we can see where time is spent and track down specific failures.
2. Logs: Record individual operations in the context of one of the request / activity.
3. Metrics: Measure counters and gauges such as successful requests, failed requests, latency etc.

### Traces view: <!-- omit from toc -->

![alt text](./assets/traces-view.png)

### Broken down trace view: <!-- omit from toc -->

![alt text](./assets/traces-expanded.png)

### Logs view: <!-- omit from toc -->

![alt text](./assets/logs.png)


## 17.3. See audit events
Either publisher or the consumer can also check for any audit events raised by the clean room during its execution for the contract by running the command below. Below instance runs the command as the `publisher-client`:
```powershell
az cleanroom governance contract event list `
    --contract-id $contractId `
    --all `
    --governance-client "publisher-client"
```
This shows output as below:
```json
{
  "value": [
    {
      "data": {
        "message": "starting execution of demo-app container",
        "source": "code-launcher"
      },
      "id": "collab1",
      "scope": "",
      "seqno": 100,
      "timestamp": "1717591984758",
      "timestamp_iso": "2024-06-05T12:53:04.758Z"
    },
    {
      "data": {
        "message": "demo-app container terminated with exit code 0",
        "source": "code-launcher"
      },
      "id": "collab1",
      "scope": "",
      "seqno": 102,
      "timestamp": "1717592058947",
      "timestamp_iso": "2024-06-05T12:54:18.947Z"
    }
  ]
}
```
# 18. Next Steps
- See how to [perform a code change](./scenarios/code-change/README.md) for the application container and redeploy a new clean room instance.
- See how to [perform upgrades](./scenarios/upgrade/README.md) of the cleanroom infrastructure components.
