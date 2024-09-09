param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,

    [Parameter(Mandatory = $true)]
    [ValidateSet("mhsm", "akvpremium")]
    [string]$kvType,

    [Parameter(Mandatory = $true)]
    [string]$outDir,

    [string]$backupKv = "",

    [string]$overridesFilePath = ""
)

$ErrorActionPreference = 'Stop'

# https://learn.microsoft.com/en-us/archive/blogs/389thoughts/get-uniquestring-generate-unique-id-for-azure-deployments
function Get-UniqueString ([string]$id, $length = 13) {
    $hashArray = (new-object System.Security.Cryptography.SHA512Managed).ComputeHash($id.ToCharArray())
    -join ($hashArray[1..$length] | ForEach-Object { [char]($_ % 26 + [byte][char]'a') })
}

$uniqueString = Get-UniqueString("${resourceGroup}")
$kvName = "${uniqueString}kv"
$hsmName = $kvType -eq "mhsm" ? "${uniqueString}mhsm" : ""

if ($overridesFilePath -ne "") {
    $overrides = Get-Content $overridesFilePath | Out-String | ConvertFrom-StringData
}
else {
    $overrides = @{}
}

mkdir -p $outDir

@"
`$RESOURCE_GROUP = "$resourceGroup"
`$RESOURCE_GROUP_LOCATION = $($overrides['$RESOURCE_GROUP_LOCATION'] ?? "`"westus`"")
`$STORAGE_ACCOUNT_NAME = $($overrides['$STORAGE_ACCOUNT_NAME'] ?? "`"${uniqueString}sa`"")
`$MHSM_NAME = $($overrides['$MHSM_NAME'] ?? "`"$hsmName`"")
`$MAA_URL = $($overrides['$MAA_URL'] ?? "`"https://sharedneu.neu.attest.azure.net`"")
`$MANAGED_IDENTITY_NAME_PREFIX = $($overrides['$MANAGED_IDENTITY_NAME_PREFIX'] ?? "`"${uniqueString}-mi`"")
`$KEYVAULT_NAME = $($overrides['$KEYVAULT_NAME'] ?? "`"$kvName`"")
`$OIDC_STORAGE_ACCOUNT_NAME = $($overrides['$OIDC_STORAGE_ACCOUNT_NAME'] ?? "`"${uniqueString}oidcsa`"")
`$OIDC_CONTAINER_NAME = $($overrides['$OIDC_CONTAINER_NAME'] ?? "`"cgs-oidc`"")
"@ > $outDir/names.generated.ps1