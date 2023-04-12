@description('Azure region that will be targeted for resources.')
param location string = resourceGroup().location

@description('Username for the VM')
param adminUsername string = 'azureuser'

@description('Type of authentication to use for the VM')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'password'

@description('SSH key or password for the VM')
@secure()
param adminPasswordOrKey string

@description('Dev VM size')
param devVmSize string = 'Standard_D4s_v4'

@description('Validator VM size')
param validatorVmSize string = 'Standard_D4s_v4'

@description('Validator VM availability zones')
param validatorAvailabilityZones string = ''

@description('RPC enabled')
param rpcEnabled bool = false

@description('RPC VM size')
param rpcVmSize string = 'Standard_D4s_v4'

@description('RPC VM availability zones')
param rpcAvailabilityZones string = ''

@description('Indexer enabled')
param indexerEnabled bool = false

@description('Indexer VM size')
param indexerVmSize string = 'Standard_D4s_v4'

@description('Indexer VM availability zones')
param indexerAvailabilityZones string = ''

// this is used to ensure uniqueness to naming (making it non-deterministic)
param rutcValue string = utcNow()

var polygonVersion = '0.8.1'

var loadBalancerName = '${uniqueString(resourceGroup().id)}lb'

// the built-in role that allow contributor permissions (create)
// NOTE: there is no built-in creator/contributor role 
var roleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: '${uniqueString(resourceGroup().id)}mi'
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  #disable-next-line use-stable-resource-identifiers simplify-interpolation
  name: '${guid(uniqueString(resourceGroup().id), rutcValue)}'
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    description: 'akvrole'
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource akv 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'a${uniqueString(resourceGroup().id)}akv'
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: [
      {
        objectId: managedIdentity.properties.principalId
        tenantId: managedIdentity.properties.tenantId
        permissions: {
          secrets: [
            'all'
          ]
        }
      }
    ]
  }
}

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
    arguments: '${managedIdentity.id} ${akv.name} ${(rpcEnabled ? 2 : 0)} ${(indexerEnabled ? 2 : 0)} ${polygonVersion}'
    forceUpdateTag: '1'
    containerSettings: {
      containerGroupName: '${uniqueString(resourceGroup().id)}ci1'
    }
    primaryScriptUri: 'https://raw.githubusercontent.com/caleteeter/polygon-azure/main/scripts/deploy.sh'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    azCliVersion: '2.28.0'
    retentionInterval: 'P1D'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: '${uniqueString(resourceGroup().id)}vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'main'
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: '${uniqueString(resourceGroup().id)}nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'rpc'
        properties: {
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '8545'
          destinationAddressPrefix: '*'
          direction: 'Inbound'
          priority: 101
        }
      }
    ]
  }
}

resource pipIdx 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: '${uniqueString(resourceGroup().id)}pipidx'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource pipRpc 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: '${uniqueString(resourceGroup().id)}piprpc'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource lb 'Microsoft.Network/loadBalancers@2022-07-01' = {
  name: loadBalancerName
  location: location
  dependsOn: [
    vnet
  ]
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'lbrpcfe'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pipRpc.id
          }
        }
      },{
        name: 'lbidxfe'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pipIdx.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'lbrpcbe'
      },{
        name: 'lbidxbe'
      }
    ]
    loadBalancingRules: [
      {
        name: 'lbrpcrule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName , 'lbrpcfe')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'lbrpcbe')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'lbprobe')
          }
          protocol: 'Tcp'
          frontendPort: 8545
          backendPort: 8545
          idleTimeoutInMinutes: 15
        }
      },{
        name: 'lbidxrule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations', loadBalancerName , 'lbidxfe')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'lbidxbe')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'lbprobe')
          }
          protocol: 'Tcp'
          frontendPort: 8545
          backendPort: 8545
          idleTimeoutInMinutes: 15
        }
      }
    ]
    probes: [
      {
        name: 'lbprobe'
        properties: {
          protocol: 'Tcp'
          port: 8545
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

module devVmModule 'modules/devVm.bicep' = {
  name: 'devDeploy'
  dependsOn: [
    deploymentScript
  ]
  params: {
    location: location
    vmSize: devVmSize
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
    authenticationType: authenticationType
    akvName: akv.name
    managedIdentity: managedIdentity.id
    nsg: nsg.id
    subnetId: vnet.properties.subnets[0].id
    totalNodes: 4
    polygonVersion: polygonVersion
  }
}

module validatorVmModule 'modules/validatorVm.bicep' = {
  name: 'validatorDeploy'
  dependsOn: [
    deploymentScript
    devVmModule
  ]
  params: {
    location: location
    vmSize: validatorVmSize
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
    authenticationType: authenticationType
    akvName: akv.name
    managedIdentity: managedIdentity.id
    nsg: nsg.id
    subnetId: vnet.properties.subnets[0].id
    totalNodes: 5
    availabilityZones: validatorAvailabilityZones
    polygonVersion: polygonVersion
  }
}

module rpcVmModule 'modules/rpcVm.bicep' = if (rpcEnabled) {
  name: 'rpcDeploy'
  dependsOn: [
    deploymentScript
  ]
  params: {
    location: location
    vmSize: rpcVmSize
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
    authenticationType: authenticationType
    akvName: akv.name
    managedIdentity: managedIdentity.id
    nsg: nsg.id
    subnetId: vnet.properties.subnets[0].id
    totalNodes: 2
    availabilityZones: rpcAvailabilityZones
    loadBalancerName: loadBalancerName
    loadBalancerBackendName: 'lbrpcbe'
    polygonVersion: polygonVersion
  }
}

module idxVmModule 'modules/idxVm.bicep' = if (indexerEnabled) {
  name: 'idxDeploy'
  dependsOn: [
    deploymentScript
  ]
  params: {
    location: location
    vmSize: indexerVmSize
    adminUsername: adminUsername
    adminPasswordOrKey: adminPasswordOrKey
    authenticationType: authenticationType
    akvName: akv.name
    managedIdentity: managedIdentity.id
    nsg: nsg.id
    subnetId: vnet.properties.subnets[0].id
    totalNodes: 2
    availabilityZones: indexerAvailabilityZones
    loadBalancerName: loadBalancerName
    loadBalancerBackendName: 'lbidxbe'
    polygonVersion: polygonVersion
  }
}

// output rpcAddress string = pipRpc.properties.ipAddress
// output idxAddress string = pipIdx.properties.ipAddress
