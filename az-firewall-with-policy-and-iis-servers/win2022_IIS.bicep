param nicName string
param vmName string
param location string
param subnetId string
param tags object
param vmSizeName string
param vmAdminUser string
@secure()
param vmAdminPass string
param vmOSDiskName string
param vmDiskType string
param availabilityZones array

// NIC deployment
resource vmNic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfiguration'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {id: subnetId}
        }
      }]
  }
}

// Windows VM deployment
resource windowsVM 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: vmName
  location: location
  tags: tags
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
      networkInterfaces: [{id: vmNic.id}]
    }
  }
  zones: availabilityZones
}

// IIS installation
resource installIIS 'Microsoft.Compute/virtualMachines/runCommands@2023-07-01' = {
  parent: windowsVM
  name: 'InstallIIS'
  location: location
  properties: {
    source: {
      script: '''
      Install-WindowsFeature -Name Web-Server -IncludeManagementTools
      $content = " VM: " + $env:COMPUTERNAME
      Set-Content C:\\inetpub\\wwwroot\\iisstart.htm $content
      '''
    }
  }
}

output privateIPAddress string = vmNic.properties.ipConfigurations[0].properties.privateIPAddress
