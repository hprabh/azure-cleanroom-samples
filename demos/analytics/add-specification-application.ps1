param(
    [string]$cleanroom_config_file,
    [string]$image = "cleanroomsamples.azurecr.io/azure-cleanroom-samples/demos/analytics@sha256:303f94478f7908c94958d1c3651a754f493e54cac23e39b9b2b096d7e8931387"
)

az cleanroom config add-application `
    --cleanroom-config $cleanroom_config_file `
    --name demos-analytics-app `
    --image $image `
    --command "python3.10 ./analytics.py" `
    --mounts "src=fabrikam-input,dst=/mnt/remote/fabrikam-input" `
             "src=contosso-input,dst=/mnt/remote/contosso-input" `
    --env-vars STORAGE_PATH_1=/mnt/remote/fabrikam-input `
               STORAGE_PATH_2=/mnt/remote/contosso-input `
    --ports 8310 `
    --cpu 0.5 `
    --memory 4

az cleanroom config set-network-policy `
    --allow-all `
    --cleanroom-config $cleanroom_config_file