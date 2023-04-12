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

# install docker
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL --max-time 10 --retry 3 --retry-delay 3 --retry-max-time 60 https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce
sudo systemctl enable docker
sleep 5

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

# create the genesis
polygon-edge genesis --block-gas-limit 10000000 --epoch-size 10 --consensus polybft --bridge-json-rpc http://10.1.1.50:8545

# fund the validator accounts
polygon-edge rootchain fund --data-dir data --num $totalNodeCount &> fund.log

# clean up secrets
rm -rf data*
