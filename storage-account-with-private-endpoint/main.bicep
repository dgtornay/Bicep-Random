// PARAMETERS
param location string = resourceGroup().location
param vnetAddress string = '10.50.0.0/16'
param subnetAddress string = '10.50.0.0/24'
param subnetBastionAdress string = '10.50.50.0/26'
param vmSizeName string = 'Standard_B2s'
param vmDiskType string = 'StandardSSD_LRS'
param vmAdminUser string = 'david'
param saSKUName string = 'Standard_LRS'

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
var saName = 'sadavid${uniqueString(resourceGroup().id)}'
var privateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var peName = 'PrivateEndpoint-sadavid'
var peDnsGroupName = '${peName}-dns'
var containerName = 'container'
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

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: saName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {name: saSKUName}
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
  }
  
  resource blobService 'blobServices' existing = {
    name: 'default'
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: storageAccount::blobService
  name: containerName
  properties: {publicAccess: 'Container'}
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${privateDnsZoneName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: true
    virtualNetwork: {id: virtualNetwork.id}
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-07-01' = {
  name: peName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: peName
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds:['blob']
        }
      }
    ]
    subnet: {
      id: '${virtualNetwork.id}/subnets/${subnetName}'
    }
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-07-01' = {
  parent: privateEndpoint
  name: peDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {privateDnsZoneId: privateDnsZone.id}
      }
    ]
  }
}

