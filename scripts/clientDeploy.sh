#!/bin/bash

managedIdentity=$1
vaultName=$2
nodeId=$3
polygonVersion=$4

# install azcli tools
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v${polygonVersion}/polygon-edge_${polygonVersion}_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# get the keys/node info 
az keyvault secret download --vault-name ${vaultName} --file node${nodeId} --name node${nodeId}
az keyvault secret download --vault-name ${vaultName} --file genesis.tar.gz --name genesis

# uncompress the genesis.json
tar xvfz genesis.tar.gz

# extract data 
base64 -d node${nodeId} > data.tar.gz
tar xvfz data.tar.gz

# run on each servers
polygon-edge server --data-dir data${nodeId} --chain genesis.json --grpc-address :5001 --libp2p :30301 --jsonrpc :10001 --seal --log-level DEBUG &> output.log &
