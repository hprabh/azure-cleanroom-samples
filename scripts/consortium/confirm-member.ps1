param(
    [string]$memberName = "$env:MEMBER_NAME",

    [string]$secretDir = "./demo-resources.secret",
    [string]$publicDir = "./demo-resources.public",

    [string]$cgsClient = "$memberName-client"
)

# Deploy client-side containers to interact with the governance service as the new member.
$ccfEndpoint = (Get-Content "$publicDir/ccfEndpoint")
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretDir/$($memberName)_cert.pem `
  --signing-key $secretDir/$($memberName)_privk.pem `
  --name $cgsClient

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client $cgsClient