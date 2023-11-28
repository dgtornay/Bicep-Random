// PARAMETERS
param location string = resourceGroup().location
param vmSizeName string = 'Standard_B2s'
param vmDiskType string = 'StandardSSD_LRS'
param vmAdminUser string = 'david'

// GLOBAL VARIABLES
var keyVaultRGName = 'RG-David-KeyVault'
var keyVaultName = 'KV-DavidGonzalez'
var tags = {
  Propietario: 'David'
}

// VNET VARIABLES
// Hub virtual network
var vnetHubName = 'vnet-hub'
var vnetHubAddress = '10.0.0.0/16'
var subnetHubFirewallName = 'AzureFirewallSubnet'
var subnetHubFirewallAddress = '10.0.0.0/24'
var subnetHubBastionName = 'AzureBastionSubnet'
var subnetHubBastionAddress = '10.0.1.0/24'

// Spoke virtual networks
var vnetSpokesArray = [
  {
    vnetSpokeName: 'vnet-spoke-a'
    vnetSpokeAddress: '10.10.0.0/16'
    subnetSpokeName: 'snet-spoke-a-web'
    subnetSpokeAddress: '10.10.0.0/24'
    suffix: '-a'
  }
  {
    vnetSpokeName: 'vnet-spoke-b'
    vnetSpokeAddress: '10.20.0.0/16'
    subnetSpokeName: 'snet-spoke-b-web'
    subnetSpokeAddress: '10.20.0.0/24'
    suffix: '-b'
  }
]


// DEPLOYMENT
// Key Vault reference
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultRGName)
}

// Hub virtual network
resource vnetHub 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetHubName
  location: location
  tags: tags
  properties: {
    addressSpace: {addressPrefixes: [vnetHubAddress]}
    subnets: [
      {
        name: subnetHubFirewallName
        properties: {addressPrefix: subnetHubFirewallAddress}
      }
      {
        name: subnetHubBastionName
        properties: {addressPrefix: subnetHubBastionAddress}
      }
      ]
  }
}

// Bastion
resource bastionPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-bastion'
  location: location
  tags: tags
  sku: {name: 'Standard'}
  properties: {publicIPAllocationMethod: 'Static'}
}

resource bastionHost 'Microsoft.Network/bastionHosts@2022-07-01' = {
  name: 'bastion'
  location: location
  tags: tags
  sku: {name: 'Standard'}
  properties: {
    ipConfigurations: [
      { 
        name: 'ipConfiguration'
        properties: {
          publicIPAddress: {id: bastionPublicIP.id}
          subnet: {id: '${vnetHub.id}/subnets/${subnetHubBastionName}'}
        }
      }]
  }
}

// Firewall
resource firewallPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-firewall'
  location: location
  tags: tags
  sku: {name: 'Standard'}
  properties: {publicIPAllocationMethod: 'Static'}
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-05-01' = {
  name: 'afwp-01'
  location: location
  tags: tags
  properties: {
    threatIntelMode: 'Alert'
  }
}

resource firewallRules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-05-01' = {
  parent: firewallPolicy
  name: 'RuleCollectionGroup-01'
  properties: {
     priority: 100
     ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        action:{type: 'DNAT'}
        name: 'Public web access'
        priority: 1000
        rules: [
          for (spoke,i) in vnetSpokesArray: {
            ruleType: 'NatRule'
            name: 'Allow public web spoke${vnetSpokesArray[i].suffix}'
            sourceAddresses: ['*']
            ipProtocols: ['TCP']
            destinationAddresses: ['${firewallPublicIP.properties.ipAddress}']
            destinationPorts: ['${i+80}']
            translatedAddress: windowwsVMIIS[i].outputs.privateIPAddress
	          translatedPort: '80'
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {type: 'Allow'}
        name: 'HTTP & ICMP interspokes'
        priority: 2000
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'Allow HTTP'
            sourceAddresses: [for spoke in vnetSpokesArray: spoke.subnetSpokeAddress]
            ipProtocols: ['TCP']
            destinationPorts: ['80','443']
            destinationAddresses: [for spoke in vnetSpokesArray: spoke.subnetSpokeAddress]
          }
          {
            ruleType: 'NetworkRule'
            name: 'Allow ICMP'
            sourceAddresses: [for spoke in vnetSpokesArray: spoke.subnetSpokeAddress]
            ipProtocols: ['ICMP']
            destinationPorts: ['*']
            destinationAddresses: [for spoke in vnetSpokesArray: spoke.subnetSpokeAddress]              
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {type: 'Allow'}
        name: 'Windows Update'
        priority: 3000
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow Windows Update'
            sourceAddresses: [for spoke in vnetSpokesArray: spoke.subnetSpokeAddress]
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
              {
                port: 443
                protocolType: 'Https'
              }
            ]
            fqdnTags: ['WindowsUpdate']
            terminateTLS: false
          }
        ]
      }
     ]
    }
  }

resource firewall 'Microsoft.Network/azureFirewalls@2023-05-01' = {
  name: 'afw'
  location: location
  tags: tags
  properties: {
    sku: {
       name: 'AZFW_VNet'
       tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'firewallIpConfiguration'
        properties: {
          publicIPAddress: {id: firewallPublicIP.id}
          subnet: {id: '${vnetHub.id}/subnets/${subnetHubFirewallName}'}
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

// Route table
resource routeTableSpokeVnets 'Microsoft.Network/routeTables@2023-05-01' = {
  name: 'rt-spokes'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'udr-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// Spoke virtual networks
resource vnetSpokes 'Microsoft.Network/virtualNetworks@2023-05-01' = [for spoke in vnetSpokesArray: {
  name: spoke.vnetSpokeName
  location: location
  tags: tags
  properties: {
    addressSpace: {addressPrefixes: [spoke.vnetSpokeAddress]}
    subnets: [
      {
        name: spoke.subnetSpokeName
        properties: {
          addressPrefix: spoke.subnetSpokeAddress
          routeTable: {id: routeTableSpokeVnets.id}
        }
      }
    ]
  }
}]

// Virtual network peerings
resource hubVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = [for (spoke,i) in vnetSpokesArray: {
  name: 'peer-hub-to-${vnetSpokes[i].name}'
  parent: vnetHub
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: {id: vnetSpokes[i].id}
  }
}]

resource spokeVnetPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = [for (spoke,i) in vnetSpokesArray: {
  name: 'peer-${vnetSpokes[i].name}-to-hub'
  parent: vnetSpokes[i]
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {id: vnetHub.id}
  }
}]

// Web Servers
module windowwsVMIIS 'win2022_IIS.bicep' = [for (spoke,i) in vnetSpokesArray: {
  name: 'Windows2022-Deployment${spoke.suffix}'
  params: {
    nicName: 'nic-web${vnetSpokesArray[i].suffix}'
    vmName: 'wvm-web${vnetSpokesArray[i].suffix}'
    location: location
    subnetId: '${vnetSpokes[i].id}/subnets/${vnetSpokesArray[i].subnetSpokeName}'
    tags: tags
    vmSizeName: vmSizeName
    vmAdminUser: vmAdminUser
    vmAdminPass: keyVault.getSecret('VM-Win2022-Pass')
    vmOSDiskName: 'osdisk-web${vnetSpokesArray[i].suffix}'
    vmDiskType: vmDiskType
    availabilityZones: []
  }
}]
