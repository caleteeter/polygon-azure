#!/bin/bash

managedIdentity=$1
vaultName=$2
rpcNodeCount=$3
idxNodeCount=$4
polygonVersion=$5

totalNodeCount=4

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v${polygonVersion}/polygon-edge_${polygonVersion}_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# install jq
apk add jq

# set the total node count to account for additional rpc and idx nodes
if [[ -n $rpcNodeCount ]]; then
    totalNodeCount=$((totalNodeCount + rpcNodeCount))     
fi

if [[ -n $idxNodeCount ]]; then
    totalNodeCount=$((totalNodeCount + idxNodeCount))
fi

# generate secrets
polygon-edge polybft-secrets --insecure --data-dir data --num $totalNodeCount

# generate secrets
for i in $(eval echo {1..$totalNodeCount} )
do
    tar -czvf data$i.tar.gz data$i
    base64 data$i.tar.gz > node$i
    az keyvault secret set --vault-name $vaultName --name node$i --file node$i
    echo "/ip4/10.1.1.1$i/tcp/1478/p2p/$(polygon-edge polybft-secrets --insecure --output --data-dir data$i --json | jq -r .[0].node_id)" > nodeid$i
    az keyvault secret set --vault-name $vaultName --name nodeid$i --file nodeid$i
done

# generate genesis configuration (only validator nodes are added as validators)
polygon-edge manifest --validators "/ip4/10.1.1.11/tcp/30301/p2p/$(polygon-edge polybft-secrets --insecure --output --data-dir data1 --json | jq -r .[0].node_id)":$(polygon-edge polybft-secrets --insecure --output --data-dir data1 --json | jq -r .[0].address):$(polygon-edge polybft-secrets --insecure --output --data-dir data1 --json | jq -r .[0].bls_pubkey):$(polygon-edge polybft-secrets --insecure --output --data-dir data1 --json | jq -r .[0].bls_signature) --validators "/ip4/10.1.1.12/tcp/30301/p2p/$(polygon-edge polybft-secrets --insecure --output --data-dir data2 --json | jq -r .[0].node_id)":$(polygon-edge polybft-secrets --insecure --output --data-dir data2 --json | jq -r .[0].address):$(polygon-edge polybft-secrets --insecure --output --data-dir data2 --json | jq -r .[0].bls_pubkey):$(polygon-edge polybft-secrets --insecure --output --data-dir data2 --json | jq -r .[0].bls_signature) --validators "/ip4/10.1.1.13/tcp/30301/p2p/$(polygon-edge polybft-secrets --insecure --output --data-dir data3 --json | jq -r .[0].node_id)":$(polygon-edge polybft-secrets --insecure --output --data-dir data3 --json | jq -r .[0].address):$(polygon-edge polybft-secrets --insecure --output --data-dir data3 --json | jq -r .[0].bls_pubkey):$(polygon-edge polybft-secrets --insecure --output --data-dir data3 --json | jq -r .[0].bls_signature) --validators "/ip4/10.1.1.14/tcp/30301/p2p/$(polygon-edge polybft-secrets --insecure --output --data-dir data4 --json | jq -r .[0].node_id)":$(polygon-edge polybft-secrets --insecure --output --data-dir data4 --json | jq -r .[0].address):$(polygon-edge polybft-secrets --insecure --output --data-dir data4 --json | jq -r .[0].bls_pubkey):$(polygon-edge polybft-secrets --insecure --output --data-dir data4 --json | jq -r .[0].bls_signature) --path ./manifest.json --premine-validators 100
polygon-edge genesis --block-gas-limit 10000000 --epoch-size 10 --consensus polybft --bridge-json-rpc http://10.1.1.50:8545

# add the genesis file to the vault
az keyvault secret set --vault-name $vaultName --name genesis --file genesis.json

# add the manifest file to the vault
az keyvault secret set --vault-name $vaultName --name manifest --file manfest.json