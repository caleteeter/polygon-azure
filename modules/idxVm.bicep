@description('Azure region that will be targeted for resources.')
param location string

@description('AKV name')
param akvName string

@description('Subnet id')
param subnetId string

@description('Load balancer name')
param loadBalancerName string

@description('Load balancer backend name')
param loadBalancerBackendName string

@description('Network security group id')
param nsg string

@description('The identity used by the VM')
param managedIdentity object

@description('The size of the virtual machine')
param vmSize string

@description('Username for the VM')
param adminUsername string

@description('Type of authentication to use for the VM')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string

@description('SSH key or password for the VM')
@secure()
param adminPasswordOrKey string

@description('Validator VM availability zones')
param availabilityZones string = ''

@description('Total nodes')
param totalNodes int

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

resource nic 'Microsoft.Network/networkInterfaces@2022-07-01' = [for i in range(0, totalNodes): {
  name: '${uniqueString(resourceGroup().id)}nic${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: '10.1.1.${int(i)+10}'
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: subnetId // vnet.properties.subnets[0].id
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
          loadBalancerBackendAddressPools: (i < 4 ? [] : (i < 6 ? [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, loadBalancerBackendName) // 'lbrpcbe')
            }
          ] : [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'lbidxbe')
            }
          ]))
        }
      }
    ]
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: nsg //.id
    }
  }
}]

resource vm 'Microsoft.Compute/virtualMachines@2022-11-01' = [for v in range(0, totalNodes): {
  name: '${uniqueString(resourceGroup().id)}vm${v}'
  location: location
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
      commandToExecute: '/bin/bash clientDeploy.sh ${managedIdentity.id} ${akvName} ${e}'
    }
  }
}]