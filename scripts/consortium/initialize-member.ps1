param(
    [string]$memberName = "$env:MEMBER_NAME",

    [string]$secretDir = "./demo-resources.secret",
    [string]$publicDir = "./demo-resources.public"
)

$memberCert = $memberName +"_cert.pem"
$encryptionCert = $memberName +"_enc_pubk.pem"

if ((Test-Path -Path "$publicDir/$memberCert") -or 
    (Test-Path -Path "$publicDir/$encryptionCert"))
{
    Write-Host "Identity and/or encryption key pairs for '$memberName' already exist in '$publicDir'" -ForegroundColor Yellow
    return
}

# Generate member identity and encryption public-private key pair.
Write-Host -"Generating identity and encryption key pairs for '$memberName' in '$secretDir'" -ForegroundColor Yellow
az cleanroom governance member keygenerator-sh | bash -s -- --gen-enc-key --name $memberName --out $secretDir

# Share the public keys for the member.
Write-Host -"Sharing public key for '$memberName' to '$publicDir'" -ForegroundColor Yellow
cp "$secretDir/$memberCert" $publicDir
cp "$secretDir/$encryptionCert" $publicDir

# Share the tenant ID.
$memberTenantId = az account show --query "tenantId" --output tsv
Write-Host -"Sharing tenant ID '$memberTenantId' for '$memberName' to '$publicDir'" -ForegroundColor Yellow
$memberTenantId > "$publicDir/$memberName.tenantid"