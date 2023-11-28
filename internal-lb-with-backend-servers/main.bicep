// PARAMETERS
param location string = resourceGroup().location
param vnetAddress string = '10.50.0.0/16'
param subnetAddress string = '10.50.0.0/24'
param subnetBastionAdress string = '10.50.50.0/26'
param subnetBackendAddress string = '10.50.10.0/24'
param vmSizeName string = 'Standard_B2s'
param vmDiskType string = 'StandardSSD_LRS'
param vmAdminUser string = 'david'

// VARIABLES
var keyVaultRGName = 'RG-David-KeyVault'
var keyVaultName = 'KeyVault-DavidGonzalez'
var vnetName = 'vnet-A'
var subnetName = 'TestSubnet'
var bastionName = 'bastion'
var subnetBastionName = 'AzureBastionSubnet'
var subnetBackendName = 'BackendSubnet'
var nameSuffix = ['-A','-B','-C']
var availabilityZones = ['1','2','3']
var testNicName = 'testNic'
var testVMName = 'testVM'
var backNicName = 'backNic'
var backVMName = 'backVM'
var vmOSDiskName = '${testVMName}_OsDisk'
var internalLBName = 'internalLB'
var frontendIPLBName = 'frontendIPLB'
var frontendIPLBAddress = '10.50.0.100'
var backendPoolName = 'backendPool'
var ruleLBName = 'ruleLB'
var healthProbeLB = 'healthProbeLB'
var tags = {
  Propietario: 'David'
}

// RESOURCES
// Key Vault reference
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultRGName)
}

// Virtual Network
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
      }
      {
        name: subnetBackendName
        properties: {addressPrefix: subnetBackendAddress}
      }]
  }
}

// Bastion
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

// Test VM
resource vmNic 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: testNicName
  location: location
  tags: tags
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
    vmName: testVMName
    location: location
    tags: tags
    vmSizeName: vmSizeName
    vmAdminUser: vmAdminUser
    vmAdminPass: keyVault.getSecret('VM-Win2022-Pass')
    vmOSDiskName: vmOSDiskName
    vmDiskType: vmDiskType
    vmNicId: vmNic.id
    availabilityZones: []
  }
}

// Backend VMs
resource backVMNic 'Microsoft.Network/networkInterfaces@2022-07-01' = [for suffix in nameSuffix: {
  name: '${backNicName}${suffix}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfiguration'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {id: '${virtualNetwork.id}/subnets/${subnetBackendName}'}
          loadBalancerBackendAddressPools: [{id: '${internalLB.id}/backendAddressPools/${backendPoolName}'}
          ]
        }
      }]
  }
}]

module backWindowwsVM 'win2022.bicep' = [for (suffix,i) in nameSuffix: {
  name: 'Windows2022-Deployment${suffix}'
  params: {
    vmName: '${backVMName}${suffix}'
    location: location
    tags: tags
    vmSizeName: vmSizeName
    vmAdminUser: vmAdminUser
    vmAdminPass: keyVault.getSecret('VM-Win2022-Pass')
    vmOSDiskName: '${vmOSDiskName}${suffix}'
    vmDiskType: vmDiskType
    vmNicId: backVMNic[i].id
    availabilityZones: [availabilityZones[i]]
  }
}]

// Load Balancer
resource internalLB 'Microsoft.Network/loadBalancers@2020-11-01' = {
  name: internalLBName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: frontendIPLBName
        properties: {
          privateIPAddress: frontendIPLBAddress
          privateIPAllocationMethod: 'Static'
          subnet: {id: '${virtualNetwork.id}/subnets/${subnetName}'}
        }
      }
    ]
    backendAddressPools:[{name: backendPoolName}]
    loadBalancingRules: [
      {
        name: ruleLBName
        properties: {
          frontendIPConfiguration: {id: resourceId('Microsoft.Network/loadBalancers/frontendIpConfigurations',internalLBName,frontendIPLBName)}
          backendAddressPool: {id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools',internalLBName,backendPoolName)}
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {id: resourceId('Microsoft.Network/loadBalancers/probes',internalLBName,healthProbeLB)}
        }
      }
    ]
    probes: [
      {
        name: healthProbeLB
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}
