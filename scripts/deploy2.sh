#!/bin/bash

managedIdentity="${1}"
resourceGroupName="${2}"
aksClusterName="${3}"
serverName="${4}"
administratorLogin="${5}"
administratorLoginPassword="${6}"

artifactsBaseUrl="https://raw.githubusercontent.com/caleteeter/polygon-azure/main"

# login
az login --identity --username "${managedIdentity}"

# get credentials for kubectl used for data plane operations
az aks install-cli
az aks get-credentials --name "${aksClusterName}" --resource-group "${resourceGroupName}"

# ensure the preview bits can be used with prompt in UI
az config set extension.use_dynamic_install=yes_without_prompt

# install the psql client
apk --no-cache add postgresql-client

# create database objects
wget -O postgresql.sql "${artifactsBaseUrl}/scripts/postgresql.sql"

# update tokens in script with real values
# shellcheck disable=SC2002
dbPass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
sed -i "s/DB_PASS/${dbPass}/g" postgresql.sql
sed -i "s/DB_ADMIN/${administratorLogin}/g" postgresql.sql

psql "host=${serverName}.postgres.database.azure.com port=5432 dbname=postgres user=${administratorLogin} password=${administratorLoginPassword} sslmode=require" -a -f "postgresql.sql"