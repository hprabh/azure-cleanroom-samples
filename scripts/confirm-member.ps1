param(
    [string]$memberName = "$env:MEMBER_NAME",
    [string]$secretsFolder = "./demo-resources.secret",
    [string]$publicFolder = "./demo-resources.public"
)

# Deploy client-side containers to interact with the governance service as the new member.
$ccfEndpoint = (Get-Content "$publicFolder/ccfEndpoint")
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretsFolder/$($memberName)_cert.pem `
  --signing-key $secretsFolder/$($memberName)_privk.pem `
  --name "$memberName-client"

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client "$memberName-client"