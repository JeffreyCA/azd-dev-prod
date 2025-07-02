// Regional deployment module for multi-region scale unit
// This module creates all regional resources for a single region
// It reuses the existing modular architecture but adds region-specific configurations
//
// Features:
// - Region-specific networking (prod vs dev)
// - Regional storage with geo-replication support
// - Regional monitoring with cross-region correlation
// - Health endpoints for Front Door probes
// - Automatic scaling and load balancing

@description('The location for regional resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Region suffix for naming (primary/secondary)')
param regionSuffix string

@description('Private DNS Zone ID for storage account (from global infrastructure)')
param privateDnsZoneStorageId string

@description('Front Door ID for access restrictions (from global infrastructure)')
param frontDoorId string = ''

// Note: Resource groups are created at the subscription level
// This regional deployment module assumes it's deployed within an existing resource group

// Deploy network infrastructure (only for production)
module regionalNetwork './network.bicep' = if (envType == 'prod') {
  name: 'regional-network-${regionSuffix}'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
  }
}

// Create VNet link to global private DNS zone (only for production)
resource privateDnsZoneStorageVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (envType == 'prod') {
  name: '${split(privateDnsZoneStorageId, '/')[8]}/${regionSuffix}-storage-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: regionalNetwork.outputs.virtualNetworkId
    }
    registrationEnabled: false
  }
  tags: tags
}

// Regional monitoring
module regionalMonitoring './monitoring.bicep' = {
  name: 'regional-monitoring-${regionSuffix}'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
    envType: envType
  }
}

// Regional managed identity
module regionalAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'regional-app-identity-${regionSuffix}'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}app-${regionSuffix}-${resourceToken}'
    location: location
    tags: tags
  }
}

// Regional shared services (storage)
module regionalShared './storage.bicep' = {
  name: 'regional-shared-${regionSuffix}'
  params: {
    location: location
    tags: union(tags, { 'region-role': regionSuffix })
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
    envType: envType
    privateEndpointSubnetId: envType == 'prod' ? regionalNetwork.outputs.privateEndpointSubnetId : ''
    privateDnsZoneStorageId: privateDnsZoneStorageId
    appIdentityPrincipalId: regionalAppIdentity.outputs.principalId
  }
}

// Regional application hosting
module regionalApp './app.bicep' = {
  name: 'regional-app-${regionSuffix}'
  params: {
    location: location
    tags: tags
    abbrs: abbrs
    resourceToken: '${regionSuffix}${resourceToken}'
    envType: envType
    vnetIntegrationSubnetId: envType == 'prod' ? regionalNetwork.outputs.vnetIntegrationSubnetId : ''
    applicationInsightsResourceId: regionalMonitoring.outputs.applicationInsightsResourceId
    appIdentityResourceId: regionalAppIdentity.outputs.resourceId
    appIdentityClientId: regionalAppIdentity.outputs.clientId
    storageAccountName: regionalShared.outputs.storageAccountName
    storageAccountBlobEndpoint: regionalShared.outputs.storageAccountBlobEndpoint
    frontDoorId: frontDoorId
    regionSuffix: regionSuffix
  }
}



// Outputs
output appServiceHostName string = regionalApp.outputs.appServiceDefaultHostname
output appServiceResourceId string = regionalApp.outputs.appServiceResourceId
output appServiceName string = regionalApp.outputs.appServiceName
output appServicePlanResourceId string = regionalApp.outputs.appServicePlanResourceId
output storageAccountName string = regionalShared.outputs.storageAccountName
output logAnalyticsWorkspaceResourceId string = regionalMonitoring.outputs.logAnalyticsWorkspaceResourceId
output applicationInsightsResourceId string = regionalMonitoring.outputs.applicationInsightsResourceId
