param(
    [string]$memberName = "$env:MEMBER_NAME",
    [string]$secretsFolder = "./demo-resources.secret",
    [string]$publicFolder = "./demo-resources.public"
)

# Generate member identity public-private key pair.
Write-Host -"Generating identity and encryption key pairs for '$memberName' in '$secretsFolder'" -ForegroundColor Yellow
az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $memberName --out $secretsFolder

# Share the public key of the member certificate.
$memberCert = $secretsFolder + "/"+ $memberName +"_cert.pem"
$encryptionCert = $secretsFolder + "/"+ $memberName +"_enc_pubk.pem"
Write-Host -"Sharing public key for '$memberName' to '$publicFolder'" -ForegroundColor Yellow
cp $memberCert $publicFolder
cp $encryptionCert $publicFolder

# Share the tenant ID.
$memberTenantId = az account show --query "tenantId" --output tsv
Write-Host -"Sharing tenant ID '$memberTenantId' for '$memberName' to '$publicFolder'" -ForegroundColor Yellow
$memberTenantId > "$publicFolder/$memberName.tenantid"