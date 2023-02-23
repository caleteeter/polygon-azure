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

@description('Availability zones')
param availabilityZones string = ''

@description('Number of RPC nodes to provision')
param rpcNodeCount int = 0

@description('Number of IDX nodes to provision')
param idxNodeCount int = 0

// this is used to ensure uniqueness to naming (making it non-deterministic)
param rutcValue string = utcNow()

var totalNodes = 4 + rpcNodeCount + idxNodeCount

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}

param vmSize string = 'Standard_D4s_v4'

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
    principalId: '${reference(managedIdentity.id).principalId}'
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
    arguments: '${managedIdentity.id} ${akv.name} ${rpcNodeCount} ${idxNodeCount}'
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

resource nic 'Microsoft.Network/networkInterfaces@2022-07-01' = [for i in range(0, totalNodes): {
  name: '${uniqueString(resourceGroup().id)}nic${i}'
  location: location
  dependsOn: [
    lb
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: '10.1.1.${int(i)+10}'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
          loadBalancerBackendAddressPools: (i < 4 ? [] : (i < 7 ? [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'lbbe')
            }
          ] : [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'lbbe')
            }
          ]))
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}]

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


resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = [for v in range(0, totalNodes): {
  name: '${uniqueString(resourceGroup().id)}vm${v}'
  location: location
  dependsOn: [
    deploymentScript
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: '${uniqueString(resourceGroup().id)}vm'
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: ((authenticationType == 'password') ? null : linuxConfiguration)
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic[v].id
        }
      ]
    }
  }
  zones: (availabilityZones == '' ? [] : [string(availabilityZones)])
}]

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = [for e in range(0, totalNodes): {
  name: '${uniqueString(resourceGroup().id)}vmext${e}'
  location: location
  parent: vm[e]
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/caleteeter/polygon-azure/main/scripts/clientDeploy.sh'
      ]
      commandToExecute: '/bin/bash clientDeploy.sh ${managedIdentity.id} ${akv.name} ${e}'
    }
  }
}]

output rpcAddress string = pipRpc.properties.ipAddress
output idxAddress string = pipIdx.properties.ipAddress
