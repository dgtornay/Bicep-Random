param vmName string
param location string
param vmSizeName string
param vmAdminUser string
@secure()
param vmAdminPass string
param vmOSDiskName string
param vmDiskType string
param vmNicId string
param userIdentityId string

resource windowsVM 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: vmName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities:{'${userIdentityId}': {}}
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSizeName
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUser
      adminPassword: vmAdminPass
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter'
        version: 'latest'
      }
      osDisk: {
        name: vmOSDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {storageAccountType: vmDiskType}
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [{id: vmNicId}]
    }
  }
}
