#!/bin/bash

sudo apt-get update
sudo apt-get install powershell -y
pwsh -v

echo 'Installing azcopy'
wget -O azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux && tar -xf azcopy_v10.tar.gz --strip-components=1
sudo mv azcopy /usr/bin
azcopy -v

echo 'Installing az confcom'
az extension add --name confcom -y

echo 'Installing az managedccfs'
az extension add --name managedccfs -y
az version