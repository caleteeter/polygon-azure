#!/bin/bash

managedIdentity=$1
vaultName=$2
rpcNodeCount=$3
idxNodeCount=$4

totalNodeCount=4

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v0.6.3/polygon-edge_0.6.3_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# set the total node count to account for additional rpc and idx nodes
if [[ -n $rpcNodeCount ]]; then
    totalNodeCount=$((totalNodeCount+rpcNodeCount))     
fi

if [[ -n $idxNodeCount ]]; then
    totalNodeCount=$((totalNodeCount+idxNodeCount))
fi

# generate secrets
for i in $( eval echo {0..$totalNodeCount} )
do
    mkdir data$i
    polygon-edge secrets init --data-dir data$i
    tar -czvf data$1.tar.gz data$i
    base64 data0.tar.gz > node$i
    az keyvault secret set --vault-name $vaultName --name node$i --file node$i
    echo "/ip4/10.1.1.10/tcp/1478/p2p/$(polygon-edge secrets output --node-id --data-dir data$i)" > nodeid$i
    az keyvault secret set --vault-name $vaultName --name nodeid$i --file nodeid$i
done

# generate genesis configuration (only validator nodes are added as validators)
polygon-edge genesis --consensus ibft --ibft-validator $(polygon-edge secrets output --data-dir data0 --validator):$(polygon-edge secrets output --data-dir data0 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data1 --validator):$(polygon-edge secrets output --data-dir data1 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data2 --validator):$(polygon-edge secrets output --data-dir data2 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data3 --validator):$(polygon-edge secrets output --data-dir data3 --bls) --bootnode $(cat nodeid0) --bootnode $(cat nodeid1) --bootnode $(cat nodeid2) --bootnode $(cat nodeid3)

# add the genesis file to the vault
az keyvault secret set --vault-name $vaultName --name genesis --file genesis.json