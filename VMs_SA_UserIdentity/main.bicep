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
var vnetName = 'vnet-1'
var subnetName = 'default'
var bastionName = 'bastion'
var subnetBastionName = 'AzureBastionSubnet'
var identityName = 'identity-VMs'
var nameSuffix = ['-A','-B']
var nicName = 'nic-win2022'
var vmName = 'vm-win2022'
var vmOSDiskName = '${vmName}-OsDisk'
var saName = 'sadavid${uniqueString(resourceGroup().id)}'
var containerName = 'container'
var saReaderRoleDefId = resourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var blobDataReaderRoleDefId = resourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var tags = {Propietario: 'David'}

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

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
  tags: tags
}

resource vmNic 'Microsoft.Network/networkInterfaces@2022-07-01' = [for suffix in nameSuffix: {
  name: '${nicName}${suffix}'
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
}]

module windowwsVM 'win2022.bicep' = [for (suffix,i) in nameSuffix: {
  name: 'Windows2022-Deployment${suffix}'
  params: {
    vmName: '${vmName}${suffix}'
    location: location
    vmSizeName: vmSizeName
    vmAdminUser: vmAdminUser
    vmAdminPass: keyVault.getSecret('VM-Win2022-Pass')
    vmOSDiskName: '${vmOSDiskName}${suffix}'
    vmDiskType: vmDiskType
    vmNicId: vmNic[i].id
    userIdentityId: userAssignedIdentity.id
  }
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: saName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {name: saSKUName}
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
  
  resource blobService 'blobServices' existing = {
    name: 'default'
  }
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: containerName
  parent: storageAccount::blobService
}

resource saReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'reader')
  scope: storageAccount
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: saReaderRoleDefId
    principalType: 'ServicePrincipal'
  }
}

resource blobDataReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'blobreader')
  scope: storageAccount
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: blobDataReaderRoleDefId
    principalType: 'ServicePrincipal'
  }
}
