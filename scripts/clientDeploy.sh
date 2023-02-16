#!/bin/bash

managedIdentity=$1
vaultName=$2
nodeId=$3

# install azcli tools
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v0.6.3/polygon-edge_0.6.3_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# get the keys/node info 
az keyvault secret download --vault-name ${vaultName} --file node${nodeId} --name node${nodeId}
az keyvault secret download --vault-name ${vaultName} --file genesis.json --name genesis

# extract data 
base64 -d node${nodeId} > data.tar.gz
tar xvfz data.tar.gz

# run on each servers
polygon-edge server --data-dir data${nodeId} --chain genesis.json --libp2p 0.0.0.0:1478 --seal &> output.log &
