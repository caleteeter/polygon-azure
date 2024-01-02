@description('Azure region that will be the target for resources')
param location string = resourceGroup().location

@description('Postgres database administrator login name')
@minLength(1)
param postgresAdminLogin string

@description('Postgres database administrator password')
@minLength(8)
@secure()
param postgresAdminPassword string

var akssubnet = 'akssubnet'
var pgsubnet = 'pgsubnet'

// allow access to all ips on the internet, for testing, will be removed or adjusted
// for production
var firewallrules= [
  {
    Name: 'allowAzure'
    StartIpAddress: '0.0.0.0'
    EndIpAddress: '0.0.0.0'
  }
  {
    Name: 'allowAllInternet'
    StartIPAddress: '0.0.0.0'
    EndIpAddress: '255.255.255.255'
  }
]

// the virtual network used by both AKS and PGaaS
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: uniqueString(resourceGroup().id)
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }

    subnets: [
      {
        name: akssubnet
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
      {
        name: pgsubnet
        properties: {
          addressPrefix: '10.1.2.0/24'
        }
      }
    ]
  }

  resource akssubnet1 'subnets' existing = {
    name: akssubnet
  }

  resource pgsubnet1 'subnets' existing = {
    name: pgsubnet
  }
}

// the identity used for internal service calls for AKS and PGaaS
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${uniqueString(resourceGroup().id)}mi'
  location: location
}

// the managed kubernetes (AKS) cluster
resource aks 'Microsoft.ContainerService/managedClusters@2022-05-02-preview' = {
  name: '${uniqueString(resourceGroup().id)}aks'
  location: location
  dependsOn: [
    vnet::akssubnet1
  ]
  properties: {
    dnsPrefix: '${uniqueString(resourceGroup().id)}aks'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 3
        vmSize: 'Standard_D4s_v4'
        mode: 'System'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets/', vnet.name, 'akssubnet')
      }
    ]
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

// the PGaaS (managed Postgres) instance
resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2022-01-20-preview' = {
  name: '${uniqueString(resourceGroup().id)}pfs'
  location: location
  sku: {
    name: 'Standard_D4ds_v4'
    tier: 'GeneralPurpose'
  }
  dependsOn: [
    vnet::pgsubnet1
  ]
  properties: {
    version: '14'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage:{
      storageSizeGB: 32
    }
  }
}

// creating the firewall rules that are applied to the PGaaS instance
@batchSize(1)
resource firewallRules 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2022-01-20-preview' = [for rule in firewallrules: {
  parent: server
  name: '${rule.Name}'
  properties: {
    startIpAddress: rule.StartIpAddress
    endIpAddress: rule.EndIpAddress
  }
}]

// the deployment script that will create assets in the PGaaS instance, initially databases, but additionally the
// k8s deployment
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${uniqueString(resourceGroup().id)}dpy'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities:{
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    arguments: '${managedIdentity.id} ${resourceGroup().name} ${aks.name} ${server.name} ${postgresAdminLogin} ${postgresAdminPassword}'
    forceUpdateTag: '1'
    containerSettings:{
      containerGroupName: '${uniqueString(resourceGroup().id)}ci1'
    }
    primaryScriptUri: 'https://raw.githubusercontent.com/caleteeter/polygon-azure/main/scripts/deploy2.sh'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    azCliVersion: '2.45.0'
    retentionInterval:'P1D'
  }
}
