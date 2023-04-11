#!/bin/bash

managedIdentity=$1
vaultName=$2
totalNodeCount=$3
polygonVersion=$4

# install azcli tools
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v${polygonVersion}/polygon-edge_${polygonVersion}_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# get the manifest from the vault
az keyvault secret download --vault-name ${vaultName} --file manifest.json --name manifest

# run on each servers
polygon-edge rootchain server &> output.log &

# deploy the bridge contracts
polygon-edge rootchain init-contracts --manifest manifest.json --json-rpc http://127.0.0.1:8545 --test &> contract_output.log

# download the secrets to be used to fund
for i in $(eval echo {1..$totalNodeCount} )
do
    az keyvault secret download --vault-name ${vaultName} --file node$i --name node$i
    base64 -d node$i > data$i.tar.gz
    tar xvfz data$i.tar.gz
done

# fund the validator accounts
polygon-edge rootchain fund --data-dir data --num $totalNodeCount &> fund.log

# clean up secrets
rm -rf data*
