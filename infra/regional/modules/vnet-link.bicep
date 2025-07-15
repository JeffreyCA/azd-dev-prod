// Module to create VNet link to global private DNS zone
// This module must be deployed in the global resource group scope

@description('The name of the private DNS zone')
param privateDnsZoneName string

@description('The virtual network ID to link')
param virtualNetworkId string

@description('The scale unit for naming (primary/secondary)')
param scaleUnit string

@description('Tags to apply to the VNet link')
param tags object = {}

// Reference the existing private DNS zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: privateDnsZoneName
}

// Create VNet link to private DNS zone
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${scaleUnit}-storage-vnet-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
    registrationEnabled: false
  }
  tags: tags
}

output vnetLinkId string = vnetLink.id
