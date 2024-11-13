param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$ccfProviderClient = "azure-cleanroom-samples-ccf-provider",
    [string]$cgsClient = "$persona-client",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$initResult = Get-Content $environmentConfig | ConvertFrom-Json
$sa = $initResult.ccfsa.id

$ccfName = $persona + "-ccf"

#
# Create a CCF instance.
#
$subscriptionId = az account show --query id --output tsv

if (!(Test-Path -Path "$privateDir/ccfProviderConfig.json"))
{
    @"
{
    "location": "$resourceGroupLocation",
    "subscriptionId": "$subscriptionId",
    "resourceGroupName": "$resourceGroup",
    "azureFiles": {
        "storageAccountId": "$sa"
    }
}
"@  | Out-File $privateDir/ccfProviderConfig.json
}

$PSNativeCommandUseErrorActionPreference = $false
# TODO : Figure out if we can use script block instead.
# & {
#     # Disable $PSNativeCommandUseErrorActionPreference for this scriptblock
#     $PSNativeCommandUseErrorActionPreference = $false
# }
$ccf = (az cleanroom ccf network show `
    --name $ccfName `
    --provider-config $privateDir/ccfProviderConfig.json `
    --provider-client $ccfProviderClient | ConvertFrom-Json)
$PSNativeCommandUseErrorActionPreference = $true

$operator = "ccf-operator"

if ($null -eq $ccf)
{
    Write-Log OperationStarted `
        "Creating consortium '$ccfName' in resource group '$resourceGroup'..."

    # Generate ccf-operator identity and encryption public-private key pair.
    $operatorMemberCert = $secretDir + "/"+ $operator + "_cert.pem"
    $operatorEncryptionCert = $secretDir + "/"+ $operator + "_enc_pubk.pem"

    if ((Test-Path -Path $operatorMemberCert) -or 
        (Test-Path -Path $operatorEncryptionCert))
    {
        Write-Log Warning `
            "Identity and/or encryption key pairs for '$operator' already exist."
    }
    else
    {
        Write-Log Verbose `
            "Generating identity and encryption key pairs for '$operator' in '$secretDir'..." 
        az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $operator --out $secretDir
    }

    $memberCert = $secretDir + "/"+ $persona + "_cert.pem"

    @"
[{
    "certificate": "$operatorMemberCert",
    "encryptionPublicKey": "$operatorEncryptionCert",
    "memberData": {
        "identifier": "$operator",
        "is_operator": true
    }
},
{
    "certificate": "$memberCert",
    "memberData": {
        "identifier": "$persona"
    }
}]
"@ | Out-File $privateDir/ccfMembers.json

    Write-Log Verbose `
        "Creating CCF network '$ccfName' in '$resourceGroup'..." 
    $ccf = (az cleanroom ccf network create `
        --name $ccfName `
        --node-count 1 `
        --node-log-level "Debug" `
        --security-policy-creation-option "allow-all" `
        --infra-type 'caci' `
        --members $privateDir/ccfMembers.json `
        --provider-config $privateDir/ccfProviderConfig.json `
        --provider-client $ccfProviderClient | ConvertFrom-Json)
    $ccfUri = $ccf.endpoint

    Write-Log OperationCompleted `
        "Created CCF network '$ccfName' ('$ccfUri')."
}
else {
    $ccfUri = $ccf.endpoint
    Write-Log Warning `
        "Connecting CCF network '$ccfName' ('$ccfUri')."
}

$response = (curl "$ccfUri/node/network" -k --silent | ConvertFrom-Json)
# Trimming an extra new-line character added to the cert.
$serviceCertStr = $response.service_certificate.TrimEnd("`n")
$serviceCert = "${ccfName}_service_cert.pem"
$serviceCertStr | Out-File "$publicDir/$serviceCert"

# Deploy client-side containers to interact with the governance service as ccf-operator
# and accept the invitation.
& {
    $persona = $operator
    $cgsClient = "$persona-client"
    az cleanroom governance client deploy `
        --ccf-endpoint $ccfUri `
        --signing-cert $secretDir/$($persona)_cert.pem `
        --signing-key $secretDir/$($persona)_privk.pem `
        --service-cert $publicDir/$serviceCert `
        --name $cgsClient

    az cleanroom governance member activate --governance-client $cgsClient

    # Configure the ccf provider client for the operator to take any operator actions like opening
    # the network.
    az cleanroom ccf provider configure `
        --name $ccfProviderClient `
        --signing-cert "$secretDir/$($operator)_cert.pem" `
        --signing-key "$secretDir/$($operator)_privk.pem" 

    # Open the network as the operator.
    Write-Log Verbose `
        "Opening CCF network '$ccfName'..." 
    az cleanroom ccf network transition-to-open `
        --name $ccfName `
        --provider-config $privateDir/ccfProviderConfig.json `
        --provider-client $ccfProviderClient
}

& {
    # Deploy client-side containers to interact with the governance service as the first member.
    az cleanroom governance client deploy `
        --ccf-endpoint $ccfUri `
        --signing-cert $secretDir/$($persona)_cert.pem `
        --signing-key $secretDir/$($persona)_privk.pem `
        --service-cert $publicDir/$($ccfName)_service_cert.pem `
        --name $cgsClient

    # Accept the invitation and becomes an active member in the consortium.
    az cleanroom governance member activate --governance-client $cgsClient

    Write-Log OperationCompleted `
        "Joined consortium '$ccfUri' and deployed CGS client '$cgsClient'."
}

# Deploy governance service on the CCF instance.
Write-Log Verbose `
    "Deploying Clean Room Governance Service to '$ccfName'..." 
az cleanroom governance service deploy --governance-client $cgsClient

# Share the CCF endpoint details.
$result = @{
    name = $ccfName
    url = $ccfUri
    serviceCert = $serviceCert
}
$result | Out-File "$ccfEndpoint"
Write-Log OperationCompleted `
    "CCF configured. Configuration written to '$ccfEndpoint'."
