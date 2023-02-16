#!/bin/bash

managedIdentity=$1
vaultName=$2

# login
az login --identity --username $managedIdentity

# retrieve polygon binaries
wget -O polygon.tar.gz https://github.com/0xPolygon/polygon-edge/releases/download/v0.6.3/polygon-edge_0.6.3_linux_amd64.tar.gz
tar xvfz polygon.tar.gz
mv polygon-edge /usr/local/bin

# generate secrets
mkdir data0 data1 data2 data3
polygon-edge secrets init --data-dir data0
polygon-edge secrets init --data-dir data1
polygon-edge secrets init --data-dir data2
polygon-edge secrets init --data-dir data3

# compress the configuration for each node
tar -czvf data0.tar.gz data0/
tar -czvf data1.tar.gz data1/
tar -czvf data2.tar.gz data2/
tar -czvf data3.tar.gz data3/

# base64 encode the compressed file for storage in AKV
base64 data0.tar.gz > node0
base64 data1.tar.gz > node1
base64 data2.tar.gz > node2
base64 data3.tar.gz > node3

# add node contents to vault
az keyvault secret set --vault-name $vaultName --name node0 --file node0
az keyvault secret set --vault-name $vaultName --name node1 --file node1
az keyvault secret set --vault-name $vaultName --name node2 --file node2
az keyvault secret set --vault-name $vaultName --name node3 --file node3

# generate p2p configuration
echo "/ip4/10.1.1.10/tcp/1478/p2p/$(polygon-edge secrets output --node-id --data-dir data0)" > nodeid0
echo "/ip4/10.1.1.11/tcp/1478/p2p/$(polygon-edge secrets output --node-id --data-dir data1)" > nodeid1
echo "/ip4/10.1.1.12/tcp/1478/p2p/$(polygon-edge secrets output --node-id --data-dir data2)" > nodeid2
echo "/ip4/10.1.1.13/tcp/1478/p2p/$(polygon-edge secrets output --node-id --data-dir data3)" > nodeid3

# add p2p configuration to vault
az keyvault secret set --vault-name $vaultName --name nodeid0 --file nodeid0
az keyvault secret set --vault-name $vaultName --name nodeid1 --file nodeid1
az keyvault secret set --vault-name $vaultName --name nodeid2 --file nodeid2
az keyvault secret set --vault-name $vaultName --name nodeid3 --file nodeid3

# generate genesis configuration
polygon-edge genesis --consensus ibft --ibft-validator $(polygon-edge secrets output --data-dir data0 --validator):$(polygon-edge secrets output --data-dir data0 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data1 --validator):$(polygon-edge secrets output --data-dir data1 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data2 --validator):$(polygon-edge secrets output --data-dir data2 --bls) --ibft-validator $(polygon-edge secrets output --data-dir data3 --validator):$(polygon-edge secrets output --data-dir data3 --bls) --bootnode $(cat nodeid0) --bootnode $(cat nodeid1) --bootnode $(cat nodeid2) --bootnode $(cat nodeid3)

# add the genesis file to the vault
az keyvault secret set --vault-name $vaultName --name genesis --file genesis.json