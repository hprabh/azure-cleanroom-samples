# Multi-party collaboration <!-- omit from toc -->

These samples demonstrate usage of clean rooms for multi-party collaboration for the following scenarios:
- Confidential read and write of protected data [using encrypted file storage](./README.md#sharing-data-using-encrypted-storage)
- Confidential [ML training](./scenarios/ml-training/README.md) fine tuning a protected ML model on protected datasets using encrypted file storage.
- Confidential [Query Analytics](./scenarios/analytics/README.md) executing audited queries on protected datasets using a standalone DB engine residing within the clean room

# Come up with some heading <!-- omit from toc -->

- [1. Overview](#1-overview)
- [2. Setting up the environment (per collaborator)](#2-setting-up-the-environment-per-collaborator)
- [3. High level execution sequence](#3-high-level-execution-sequence)
- [4. Setup the consortium](#4-setup-the-consortium)
  - [4.1. Member identity creation (ISV, publisher, consumer)](#41-member-identity-creation-isv-publisher-consumer)
  - [4.4. Invite members to the consortium (ISV)](#44-invite-members-to-the-consortium-isv)
  - [4.5. Join the consortium (publisher, consumer)](#45-join-the-consortium-publisher-consumer)
- [5. Protecting data shared for collaboration](#5-protecting-data-shared-for-collaboration)
  - [5.1. KEK-DEK based encryption approach](#51-kek-dek-based-encryption-approach)
  - [5.2. Encrypt and upload data](#52-encrypt-and-upload-data)
- [7. Publisher: Setting up log collection](#7-publisher-setting-up-log-collection)
- [8. Share publisher clean room configuration with consumer](#8-share-publisher-clean-room-configuration-with-consumer)
- [9. Consumer: Output preparation and application configuration](#9-consumer-output-preparation-and-application-configuration)
  - [9.2. Application configuration and mount points](#92-application-configuration-and-mount-points)
    - [9.2.1. Mounting storage containers using Blobfuse2](#921-mounting-storage-containers-using-blobfuse2)
- [10. Proposing a governance contract](#10-proposing-a-governance-contract)
- [11. Agreeing upon the contract](#11-agreeing-upon-the-contract)
  - [11.1. Agree as publisher](#111-agree-as-publisher)
  - [11.2. Agree as consumer](#112-agree-as-consumer)
- [12. Propose ARM template, CCE policy and log collection](#12-propose-arm-template-cce-policy-and-log-collection)
- [13. Accept ARM template, CCE policy and logging proposals](#13-accept-arm-template-cce-policy-and-logging-proposals)
  - [13.1. Verify and accept as publisher](#131-verify-and-accept-as-publisher)
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
  - [Contributing](#contributing)
  - [Trademarks](#trademarks)


# 1. Overview
All the scenarios demonstrate a collaboration where 3 parties come together:
  - A publisher (party 1) having dataset(s) meant to be consumed via the collaboration.
  - A consumer (party 2) that wants to run an application that consumes the data shared by the publisher. This party might also bring in its own dataset(s) into the collaboration. The consumer requires any confidential output generated from the clean room should only be accessible by the consumer.
  - An ISV (party 3) hosting the confidential clean room infrastructure.

In all cases, a confidential clean room (CCR) will be executed to run the consumer's application while protecting the privacy of the data that is ingested for both the publisher and the consumer, as well as protected any output for the consumer. The clean room can be deployed by either of the 2 parties or the ISV without any impact on the zero-trust promise architecture.

Capabilities demonstrated:
- How to prepare encrypted data as input that can be read only from a clean room
- How to get encrypted data as output from  the clean room that can only read by one of the parties
- How to exchange information about the encrypted data sets and code application between the collaborating parties
- How to create a governance contract capturing what data is exposed and what code runs in the clean room
- How to agree upon the ARM template and CCE policy that will be used for the clean room deployment
- How to enable clean room execution logs collection and inspect the same in a confidential manner

# 2. Setting up the environment (per collaborator)
All the involved parties need to bring up a local environment to participate in the collaboration. This can be achieved either by launching a pre-configured docker container (preferred) or by executing the configuration steps by hand.

<details><summary>Using a pre-configured docker container</summary>
<br>
To set this infrastructure up, we will need Docker installed locally. Installation instructions [here](https://docs.docker.com/engine/install/).

<br>

  ```powershell
  ./build.ps1

  # Set name to be associated with this party for the collaboration.
  $memberName = "<friendly name>"
  ./launch.ps1 -memberName $memberName
  ```
</details>
<br>
<details><summary>Executing the configuration steps by hand</summary>
<br>

We recommend running the following steps in PowerShell on WSL using Ubuntu 22.04.
- Instructions for setting up WSL can be found [here](https://learn.microsoft.com/en-us/windows/wsl/install).
- To install PowerShell on WSL, follow the instructions [here](https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.3).

To set this infrastructure up, we will need the following tools to be installed prior to running the setup scripts.
1. Azure CLI version >= 2.57. Installation instructions [here](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux).
2. You need Docker for Linux installed locally. Installation instructions [here](https://docs.docker.com/engine/installation/#supported-platforms).
3. Confidential containers Azure CLI extension, version >= 0.3.5. You can install this extension using ```az extension add --name confcom -y```. You can check the version of the extension using ```az extension show --name confcom```. Learn about it [here](https://learn.microsoft.com/en-us/cli/azure/confcom?view=azure-cli-latest).
4. Managed CCF Azure CLI extension. You can install this extension using ```az extension add --name managedccfs -y```.
5. azcopy versions >= 10.25.0. Installation instructions [here](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10).
6. openssl - Download instructions for Linux [here](https://www.openssl.org/source/).
7. jq - Download / install instructions for Linux [here](https://jqlang.github.io/jq/download/).
8. Add the CleanRoom Azure CLI extension using:
    ```powershell
    az extension add --source https://cleanroomazcli.blob.core.windows.net/azcli/cleanroom-0.0.3-py2.py3-none-any.whl -y --allow-preview true
    ```

</details>
<br>

> [!NOTE]
> An Azure subscription with adequate permissions to create resources and manage permissions on these resources is required for executing all the samples.

Once the environment is setup, ensure that you are logged into Azure, set the subscription (if required) and create the resource group for executing the samples.
```powershell
# Login to Azure.
az login

# Set active subscription (optional).
az account set --subscription "<subname>"

az group create --name $env:RESOURCE_GROUP --location westus
```

# 3. High level execution sequence
Before we begin below gives the overall flow of execution that happens in this sample. It gives a high level perspective that might be helpful to keep in mind as you run through the steps.
```mermaid
sequenceDiagram
    title Collaboration flow
    participant m2 as ISV
    participant m1 as Publisher
    participant m0 as Consumer
    participant CCF as Clean Room Governance<br>(CCF instance)
    participant CACI as Clean Room<br> (C-ACI instance)

    m2->>CCF: Creates consortium
    m1->>CCF: Joins consortium
    m0->>CCF: Joins consortium
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
    m2->>CACI: Deploys clean room
    CACI->>CCF: Check execution consent
    CACI->>CCF: Get tokens for Azure resource access
    CACI->>CACI: Access secrets in Key Vault
    CACI->>CACI: Access encrypted storage
    CACI->>CACI: Write out result to encrypted storage
    m0->>CACI: Waits for result
    m1->>m0: Shares application logs
```
<br>
Once the clean room is deployed the key components involved during execution are shown below:

![alt text](./assets/encrypted-storage-layout.png)

> [!NOTE]
> The steps henceforth assume that you are working in the `/home/samples` directory of the docker container and all commands are executed relative to that.

# 4. Setup the consortium
This collaboration between the publisher and the consumer is realized by creating a [consortium in CCF](https://microsoft.github.io/CCF/main/overview/what_is_ccf.html) which runs a [clean room governance service](../../src/governance/README.md) where both the publisher and consumer become the participating members. Each CCF consortium member is identified by a public-key certificate used for client authentication and command signing. 

As the first step of the collaboration, a CCF instance needs to be created with the above members. From a confidentiality perspective any of the collaborators or the ISV can create the CCF instance without affecting the zero-trust assurances. In these samples, we assume that it was agreed upon that the ISV will host the CCF instance. The ISV would create the CCF instance and then invite the publisher and consumer as members into the consortium.

```mermaid
sequenceDiagram
    title Consortium creation flow
    participant m2 as ISV
    participant m1 as Publisher
    participant m0 as Consumer
    participant CCF as CCF instance

    m2->>CCF: Create mCCF instance
    CCF-->>m2: CCF created
    m2->>CCF: Activate membership
    Note over CCF: ISV active
    m2->>CCF: Deploy governance service
    CCF-->>m2: State: Service deployed
    m1->>m2: Share publisher identity cert
    m2->>CCF: Propose adding publisher as member
    CCF-->>m2: Proposal ID
    m2->>CCF: Vote for Proposal ID
    Note over CCF: Publisher accepted
    CCF-->>m2: State: Accepted
    m0->>m2: Share consumer identity cert
    m2->>CCF: Propose adding consumer as member
    CCF-->>m2: Proposal ID
    m2->>CCF: Vote for Proposal ID
    Note over CCF: Consumer accepted
    CCF-->>m2: State: Accepted
    m2->>m1: Share ccfEndpoint URL eg.<br>https://<name>.confidential-ledger.azure.com
    m2->>m0: Share ccfEndpoint URL eg.<br>https://<name>.confidential-ledger.azure.com
    m1->>CCF: Verifies state of the consortium
    m1->>CCF: Activate membership
    Note over CCF: Publisher active
    m0->>CCF: Verifies state of the consortium
    m0->>CCF: Activate membership
    Note over CCF: Consumer active
```

## 4.1. Member identity creation (ISV, publisher, consumer)
The identity public and private key pairs for all members needs be created. Each member of the collaboration creates their member identity.

```powershell
$secretsFolder = "./demo-resources.secret"

az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $env:MEMBER_NAME --out $secretsFolder


```
Above command shows output similar to below.
```
-- Generating identity private key and certificate for participant "contosso"...
Identity curve: secp384r1
Identity private key generated at:   ./demo-resources.secret/contosso_privk.pem
Identity certificate generated at:   ./demo-resources.secret/contosso_cert.pem (to be registered in CCF)
-- Generating RSA encryption key pair for participant "contosso"...
writing RSA key
Encryption private key generated at:  ./demo-resources.secret/contosso_enc_privk.pem
Encryption public key generated at:   ./demo-resources.secret/contosso_enc_pubk.pem (to be registered in CCF)
```

The above command will generate the public/private key pair. The member’s identity private key should be stored on a trusted device (e.g. HSM) and kept private (not shared with any other member) while the certificate (e.g. membername_cert.pem) would be registered in CCF (later in the flow).


## 4.2. Create the CCF instance (ISV)<!-- omit from toc -->

Run the below steps to create the CCF instance.
```powershell
$secretsFolder = "./demo-resources.secret"

# Create the mCCF instance.
$ccfName = $env:RESOURCE_GROUP + "-ccf"
$memberCert = $secretsFolder + "/"+ $env:MEMBER_NAME +"_cert.pem" # Created previously via the keygenerator-sh command.
az confidentialledger managedccfs create `
    --name $ccfName `
    --resource-group $env:RESOURCE_GROUP `
    --location "southcentralus" `
    --members "[{certificate:'$memberCert',identifier:'$env:MEMBER_NAME'}]"
$ccfEndpoint = (az confidentialledger managedccfs show `
    --resource-group $env:RESOURCE_GROUP `
    --name $ccfName `
    --query "properties.appUri" `
    --output tsv)

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretsFolder/$($env:MEMBER_NAME)_cert.pem `
  --signing-key $secretsFolder/$($env:MEMBER_NAME)_privk.pem `
  --name "$env:MEMBER_NAME-client"

# Activate membership.
az cleanroom governance member activate --governance-client "$env:MEMBER_NAME-client"

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client "$env:MEMBER_NAME-client"

# Set tenant Id as a part of the member data. This is required to enable OIDC provider in the later steps.
$memberTenantId = az account show --query "tenantId" --output tsv
$proposalId = (az cleanroom governance member set-tenant-id `
  --identifier "$env:MEMBER_NAME" `
  --tenant-id $memberTenantId `
  --query "proposalId" `
  --output tsv `
  --governance-client "$env:MEMBER_NAME-client")

az cleanroom governance proposal vote `
  --proposal-id $proposalId `
  --action accept `
  --governance-client "$env:MEMBER_NAME-client"
```

## 4.3. Publish member certificate public key and tenant ID (publisher, consumer)<!-- omit from toc -->
Once the CCF instance is created with the ISV as the initial member, the next step is to add the publisher and consumer into the consortium. For this the publisher and consumer need to share their identity public key (`<membername>_cert.pem`) and the Tenant ID with the ISV:
```powershell
$secretsFolder = "./demo-resources.secret"
$publicFolder = "./demo-resources.public"

$memberCert = $secretsFolder + "/"+ $env:MEMBER_NAME +"_cert.pem"
cp $memberCert $publicFolder

$encryptionCert = $secretsFolder + "/"+ $env:MEMBER_NAME +"_enc_pubk.pem"
cp $encryptionCert $publicFolder

# Determining tenant ID.
$memberTenantId = az account show --query "tenantId" --output tsv
echo $memberTenantId > "$publicFolder/$env:MEMBER_NAME.tenantid"
```

## 4.4. Invite members to the consortium (ISV)
For each member of the collaboration, the ISV (who is hosting the CCF instance) needs to run the below commands:

```powershell
$publicFolder = "./demo-resources.public"
$collaborators = 'fabrikam', 'contosso'

foreach ($collaboratorName in $collaborators)
{
    # Makes a proposal for adding the new member.
    $proposalId = (az cleanroom governance member add `
        --certificate $publicFolder/$($collaboratorName)_cert.pem `
        --identifier $collaboratorName `
        --tenant-id (Get-Content "$publicFolder/$collaboratorName.tenantid") `
        --query "proposalId" `
        --output tsv `
        --governance-client "$env:MEMBER_NAME-client")

    # Vote on the above proposal to accept the membership.
    az cleanroom governance proposal vote `
        --proposal-id $proposalId `
        --action accept `
        --governance-client "$env:MEMBER_NAME-client"
}

```

## 4.5. Join the consortium (publisher, consumer)
Once the publisher and consumer have been added, they now need to activate their membership before they can participate in the collaboration. The ISV must share the `ccfEndpoint` value to the publisher and consumer so they can know which CCF instance to connect to.

```powershell
$ccfEndpoint = "<CCF Endpoint>"
$secretsFolder = "./demo-resources.secret"

# "Deploy client-side containers to interact with the governance service as the new member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretsFolder/$($env:MEMBER_NAME)_cert.pem `
  --signing-key $secretsFolder/$($env:MEMBER_NAME)_privk.pem `
  --name "$env:MEMBER_NAME-client"

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client "$env:MEMBER_NAME-client"
```
With the above steps the consortium creation that drives the creation and execution of the clean room is complete. We now proceed to preparing the datasets and making them available in the clean room.

> [!NOTE]
> The same consortium can be used/reused for executing any/all the sample scenarios. There is no need to repeat these steps unless the collaborators have changed. 

# 5. Protecting data shared for collaboration
## 5.1. KEK-DEK based encryption approach
The data that the publisher/consumer want to bring into the collaboration would be encrypted by the respective parties such that the key to decrypt the same will only be released to the clean room environment. The sample follows an envelope encryption model for encryption of data. For the encryption of the data *Data Encryption Keys* (DEK) are generated, which are symmetric in nature. An asymmetric key, called the *Key Encryption Key* (KEK), is generated subsequently to wrap the DEK. The wrapped DEKs are stored in a Key Vault as a secret and the KEK is imported into an MHSM/Premium Key Vault behind a secure key release (SKR) policy. Within the clean room, the wrapped DEK is read from the Key Vault and the KEK is retrieved from the MHSM/Premium Key Vault following the [secure key release](https://learn.microsoft.com/en-us/azure/confidential-computing/concept-skr-attestation) protocol. The DEKs are unwrapped within the cleanroom and then used to access the storage containers.

The parties can choose between a Managed HSM or a Premium Azure Key Vault for storing their encryption keys passing the `-kvType` paramter to the scripts below.

## 5.2. Encrypt and upload data
It is assumed that the publisher and consumer have had out-of-band communication and have agreed on the data sets that will be shared. In these samples it is assumed that the protected data is in the form of one or more files in one or more folders at the publisher's and consumer's end.

The setup involves creating an Azure resource group into which a storage account and a Managed HSM or Premium Key Vault are deployed. The dataset(s) in the form of files are encrypted (using the KEK-DEK approach mentioned earlier) and uploaded into the the storage account. Each folder in the source dataset would correspond to one storage container, and all files in that folder are [uploaded as blobs to Azure Storage using Customer Provided Keys](https://learn.microsoft.com/azure/storage/blobs/encryption-customer-provided-keys). The sample creates one symmetric key per folder (storage container).

```mermaid
sequenceDiagram
    title Encrypting and uploading data to Azure Storage
    participant m1 as Collaborator
    participant storage as Azure Storage
    participant akv as Azure Key Vault
    participant mi as Managed Identity

    m1->>akv: Create Key Vault
    Note over m1: Key Vault will be used later <br>to save the wrapped DEKs
    loop every dataset folder
        m1->>m1: Generate symmetric key (DEK) per folder
        m1->>storage: Create storage container for folder
        loop every file in folder
            m1->>storage: Encrypt file using DEK and upload to container
        end
    end
```
Initialize Azure resources required for running samples from this repository by executing the following command from the `/home/samples` directory:
```powershell
# Create storage account and KV.
$resourceResult = (./scripts/prepare-resources.ps1 -kvType akvpremium)
```

Publish datasets for running the demo by executing the following command from the `/home/samples` directory. This initializes datastores and uploads encrypted datasets required for executing the samples:
```powershell
$scenario = "analytics"

# Publish data. 
# Storage account is picked from ./demo-resources.private/$env:RESOURCE_GROUP.generated.json
# by default, use -sa to override.
./demos/$scenario/publish-data.ps1 -persona $env:MEMBER_NAME
```

```powershell
$configResult = (./scripts/init-config.ps1 -scenario $scenario)
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
./demos/$scenario/add-config-data.ps1 -persona $env:MEMBER_NAME
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
./scripts/config-telemetry.ps1 -scenario $scenario
```

# 8. Share publisher clean room configuration with consumer
For the consumer to configure their application to access the data from the publisher it needs to know the details about the datasources that have been prepared by the publisher. Eg the consumer needs to refer to the individual datasources by their name when specifying where to mount each datasource in the container. The publisher needs to share the `publisher-config` file with the consumer.

# 9. Consumer: Output preparation and application configuration
## 9.2. Application configuration and mount points
The application details such as the app name, container registry, image ID, command, environment variables and resources needs to be captured as below. Replace the values for the parameters as appropriate.

The sample application is located at `consumer-demo/application` directory. It is a `golang` application that reads a text file from `INPUT_LOCATION`, compresses it and writes the archive out to `OUTPUT_LOCATION`. The below command adds the application details to the configuration file.
```powershell
az cleanroom config init --cleanroom-config ./demo-resources.private/analysis.config

./demos/analytics/add-config-application.ps1 -cleanroom_config_file ./demo-resources.private/analysis.config

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
    --cleanroom-config ./demo-resources.private/analysis.config `
    --configs ./demo-resources.public/fabrikam.config ./demo-resources.public/contosso.config `
    > ./demo-resources.public/analysis.cleanroom.config

# Validate the contract structure before proposing.
az cleanroom config validate --cleanroom-config ./demo-resources.public/analysis.cleanroom.config

$contractId = "collab1" # A unique identifier to refer to this collaboration.
$data = Get-Content -Raw ./demo-resources.public/analysis.cleanroom.config
az cleanroom governance contract create `
    --data "$data" `
    --id $contractId `
    --governance-client "$env:MEMBER_NAME-client"

# Submitting a contract proposal.
$version = (az cleanroom governance contract show `
    --id $contractId `
    --query "version" `
    --output tsv `
    --governance-client "$env:MEMBER_NAME-client")

az cleanroom governance contract propose `
    --version $version `
    --id $contractId `
    --query "proposalId" `
    --output tsv `
    --governance-client "$env:MEMBER_NAME-client"
```
The above command creates a contract in the governance service with the clean room specification yaml as its contents. Next both the consumer and publisher inspect the proposed contract and accept after verification.

# 11. Agreeing upon the contract
The publisher/client can now query CCF to get the proposed contract, run their validations and accept or reject the contract. To achieve this:

## 11.1. Agree as publisher 
```powershell
$contract = (az cleanroom governance contract show `
    --id $contractId `
    --governance-client "$env:MEMBER_NAME-client" | ConvertFrom-Json)

# Inspect the contract details that is capturing the storage, application container and identity details.
$contract.data

# Accept it.
az cleanroom governance contract vote `
    --id $contractId `
    --proposal-id $contract.proposalId `
    --action accept `
    --governance-client "$env:MEMBER_NAME-client"
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
mkdir ./demo-resources.public/$contractId

az cleanroom governance deployment generate `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client" `
    --output-dir ./demo-resources.public/$contractId
```
> [!NOTE]
> The above command invokes `az confcom acipolicygen` and takes around 10-15 minutes to finish.

Once run, this creates the following files in the output directory specified above: 
 1. `cleanroom-arm-template.json`. This is the ARM template that can be deployed. This has the base64 encoded CCE policy embedded in it.
 2. `cleanroom-governance-policy.json`. This file contains the clean room policy which identifies this clean room when its under execution.

Now propose the template and policy along with also submitting a proposal for enabling log collection.

```powershell
az cleanroom governance deployment template propose `
    --template-file ./demo-resources.public/$contractId/cleanroom-arm-template.json `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client"

az cleanroom governance deployment policy propose `
    --policy-file ./demo-resources.public/$contractId/cleanroom-governance-policy.json `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client"

# Propose enabling log and telemetry collection during cleanroom execution.
az cleanroom governance contract runtime-option propose `
    --option logging `
    --action enable `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client"

az cleanroom governance contract runtime-option propose `
    --option telemetry `
    --action enable `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client"
```

The generated ARM template and CCE policy are raised as proposals in the governance service on the same contract that was accepted. The proposals can be inspected as follows:
```powershell
# Inspect the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client" `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args.spec.data" `
    --governance-client "$env:MEMBER_NAME-client"

# Inspect the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client "$env:MEMBER_NAME-client" `
    --query "proposalIds[0]" `
    --output tsv

az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args" `
    --governance-client "$env:MEMBER_NAME-client"
```

# 13. Accept ARM template, CCE policy and logging proposals
Once the ARM template and CCE policy proposals are available, the remaining parties can validate and vote on these proposals. In this sample, we run a simple validation and accept the template and CCE policy.

## 13.1. Verify and accept as publisher
Run the following as the publisher.
```powershell
./scripts/accept-deployment-proposals.ps1 -contractId $contractId
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


## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
