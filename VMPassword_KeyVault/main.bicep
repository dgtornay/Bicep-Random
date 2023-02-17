// PARAMETERS
param location string = resourceGroup().location
param vnetAddress string = '10.50.0.0/16'
param subnetAddress string = '10.50.0.0/24'
param subnetBastionAdress string = '10.50.50.0/26'
param vmSizeName string = 'Standard_B2s'
param vmDiskType string = 'StandardSSD_LRS'
param vmAdminUser string = 'david'

// VARIABLES
var keyVaultRGName = 'RG-David-KeyVault'
var keyVaultName = 'KeyVault-DavidGonzalez'
var vnetName = 'vnet-A'
var subnetName = 'default'
var bastionName = 'bastion'
var subnetBastionName = 'AzureBastionSubnet'
var nicName = 'nic-win2022-A'
var vmName = 'vm-win2022-A'
var vmOSDiskName = '${vmName}_OsDisk'
var tags = {
  Propietario: 'David'
}

// RESOURCES
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultRGName)
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {addressPrefixes: [vnetAddress]}
    subnets: [
      {
        name: subnetName
        properties: {addressPrefix: subnetAddress}
      }
      {
        name: subnetBastionName
        properties: {addressPrefix: subnetBastionAdress}
      }]
  }
}

resource bastionPublicIP 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: '${bastionName}-PIP'
  location: location
  tags: tags
  sku: {name: 'Standard'}
  properties: {publicIPAllocationMethod: 'Static'}
}

resource bastionHost 'Microsoft.Network/bastionHosts@2022-07-01' = {
  name: bastionName
  location: location
  tags: tags
  sku: {name: 'Standard'}
  properties: {
    ipConfigurations: [
      { 
        name: 'ipConfiguration'
        properties: {
          publicIPAddress: {id: bastionPublicIP.id}
          subnet: {id: '${virtualNetwork.id}/subnets/${subnetBastionName}'}
        }
      }]
  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfiguration'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {id: '${virtualNetwork.id}/subnets/${subnetName}'}
        }
      }]
  }
}

module windowwsVM 'win2022.bicep' = {
  name: 'Windows2022-Deployment'
  params: {
    vmName: vmName
    location: location
    vmSizeName: vmSizeName
    vmAdminUser: vmAdminUser
    vmAdminPass: keyVault.getSecret('VM-Win2022-Pass')
    vmOSDiskName: vmOSDiskName
    vmDiskType: vmDiskType
    vmNicId: vmNic.id
  }
}
