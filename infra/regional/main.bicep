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

@description('Scale unit for naming (primary/secondary)')
param scaleUnit string

@description('Private DNS Zone ID for storage account (from global infrastructure)')
param privateDnsZoneStorageId string

@description('Front Door ID for access restrictions (from global infrastructure)')
param frontDoorId string = ''

// Create regional tags by adding the scale-unit tag to the base tags
var regionalTags = union(tags, { 'scale-unit': scaleUnit })

// Note: Resource groups are created at the subscription level
// This regional deployment module assumes it's deployed within an existing resource group

// Deploy network infrastructure (only for production)
module regionalNetwork './network.bicep' = if (envType == 'prod') {
  name: 'regional-network-${scaleUnit}'
  params: {
    location: location
    tags: regionalTags
    abbrs: abbrs
    resourceToken: '${scaleUnit}${resourceToken}'
  }
}

// Get VNet outputs when in production mode
var vnetIntegrationSubnetId = envType == 'prod' ? regionalNetwork!.outputs.vnetIntegrationSubnetId : ''
var privateEndpointSubnetId = envType == 'prod' ? regionalNetwork!.outputs.privateEndpointSubnetId : ''
var virtualNetworkId = envType == 'prod' ? regionalNetwork!.outputs.virtualNetworkId : ''

// Regional monitoring
module regionalMonitoring './monitoring.bicep' = {
  name: 'regional-monitoring-${scaleUnit}'
  params: {
    location: location
    tags: regionalTags
    abbrs: abbrs
    resourceToken: '${scaleUnit}${resourceToken}'
    envType: envType
  }
}

// Regional managed identity
module regionalAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'regional-app-identity-${scaleUnit}'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}app-${scaleUnit}-${resourceToken}'
    location: location
    tags: regionalTags
  }
}

// Regional shared services (storage)
module regionalShared './storage.bicep' = {
  name: 'regional-shared-${scaleUnit}'
  params: {
    location: location
    tags: regionalTags
    abbrs: abbrs
    resourceToken: '${scaleUnit}${resourceToken}'
    envType: envType
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneStorageId: privateDnsZoneStorageId
    appIdentityPrincipalId: regionalAppIdentity.outputs.principalId
  }
  dependsOn: envType == 'prod' ? [regionalNetwork] : []
}

// Regional application hosting
module regionalApp './app.bicep' = {
  name: 'regional-app-${scaleUnit}'
  params: {
    location: location
    tags: regionalTags
    abbrs: abbrs
    resourceToken: '${scaleUnit}${resourceToken}'
    envType: envType
    vnetIntegrationSubnetId: vnetIntegrationSubnetId
    applicationInsightsResourceId: regionalMonitoring.outputs.applicationInsightsResourceId
    appIdentityResourceId: regionalAppIdentity.outputs.resourceId
    appIdentityClientId: regionalAppIdentity.outputs.clientId
    storageAccountName: regionalShared.outputs.storageAccountName
    storageAccountBlobEndpoint: regionalShared.outputs.storageAccountBlobEndpoint
    frontDoorId: frontDoorId
    scaleUnit: scaleUnit
  }
  dependsOn: envType == 'prod' ? [regionalNetwork] : []
}



// Outputs
output appServiceHostName string = regionalApp.outputs.appServiceDefaultHostname
output appServiceResourceId string = regionalApp.outputs.appServiceResourceId
output appServiceName string = regionalApp.outputs.appServiceName
output appServicePlanResourceId string = regionalApp.outputs.appServicePlanResourceId
output storageAccountName string = regionalShared.outputs.storageAccountName
output logAnalyticsWorkspaceResourceId string = regionalMonitoring.outputs.logAnalyticsWorkspaceResourceId
output applicationInsightsResourceId string = regionalMonitoring.outputs.applicationInsightsResourceId
output virtualNetworkId string = envType == 'prod' ? virtualNetworkId : ''
