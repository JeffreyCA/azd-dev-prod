// Multi-Region Scale Unit Main Infrastructure
// This is the main entry point for deploying a multi-region scale unit
//
// Architecture:
// - Primary and secondary regions with App Services
// - Azure Front Door for global load balancing
// - Geo-replicated storage for data consistency
// - Cross-region monitoring and alerting
// - Environment-specific networking (VNet integration for prod)
//
// Usage:
// - Deploy with envType='dev' for simplified multi-region setup
// - Deploy with envType='prod' for full VNet integration and private endpoints

targetScope = 'subscription'

metadata name = 'Multi-Region Scale Unit'
metadata description = 'Deploys a highly available multi-region application with Azure Front Door'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@metadata({azd: { 
  type: 'location'
  default: 'eastus'
}})
@description('Primary location for resources')
param primaryLocation string

@metadata({azd: { 
  type: 'location'
  default: 'westus2'
}})
@description('Secondary location for resources')
param secondaryLocation string

@description('Environment type - determines networking configuration (dev/test/prod)')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

var primaryResourceGroupName string = 'rg-${environmentName}-primary'
var secondaryResourceGroupName string = 'rg-${environmentName}-secondary'
var globalResourceGroupName string = 'rg-${environmentName}-global'

// Tags that should be applied to all resources.
var tags = {
  'azd-env-name': environmentName
  'environment-type': envType
  'scale-unit': 'multi-region'
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, primaryLocation)

resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: primaryResourceGroupName
  location: primaryLocation
  tags: union(tags, { 'region-role': 'primary' })
}

resource secondaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: secondaryResourceGroupName
  location: secondaryLocation
  tags: union(tags, { 'region-role': 'secondary' })
}

resource globalResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: globalResourceGroupName
  location: primaryLocation
  tags: union(tags, { 'region-role': 'global' })
}

// Deploy global infrastructure (Front Door profile, global storage, DNS zones)
module globalInfrastructure './global/main.bicep' = {
  name: 'globalInfrastructureDeployment'
  scope: globalResourceGroup
  params: {
    primaryLocation: primaryLocation
    tags: tags
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
  }
}

// Deploy primary region infrastructure
module primaryRegion './regional/main.bicep' = {
  name: 'primaryRegionDeployment'
  scope: primaryResourceGroup
  params: {
    location: primaryLocation
    tags: tags
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    scaleUnit: 'primary'
    privateDnsZoneStorageId: globalInfrastructure.outputs.privateDnsZoneStorageId
    frontDoorId: globalInfrastructure.outputs.frontDoorId
  }
}

// Deploy secondary region infrastructure
module secondaryRegion './regional/main.bicep' = {
  name: 'secondaryRegionDeployment'
  scope: secondaryResourceGroup
  params: {
    location: secondaryLocation
    tags: tags
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    scaleUnit: 'secondary'
    privateDnsZoneStorageId: globalInfrastructure.outputs.privateDnsZoneStorageId
    frontDoorId: globalInfrastructure.outputs.frontDoorId
  }
}

// Create VNet links for private DNS zone (only for production)
module primaryVnetLink './regional/modules/vnet-link.bicep' = if (envType == 'prod') {
  name: 'primaryVnetLinkDeployment'
  scope: globalResourceGroup
  params: {
    privateDnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkId: primaryRegion.outputs.virtualNetworkId
    scaleUnit: 'primary'
    tags: tags
  }
}

module secondaryVnetLink './regional/modules/vnet-link.bicep' = if (envType == 'prod') {
  name: 'secondaryVnetLinkDeployment'
  scope: globalResourceGroup
  params: {
    privateDnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkId: secondaryRegion.outputs.virtualNetworkId
    scaleUnit: 'secondary'
    tags: tags
  }
}

// Configure Front Door endpoints and origins after App Services are created
module frontDoorConfig './global/front-door-config.bicep' = {
  name: 'frontDoorConfigDeployment'
  scope: globalResourceGroup
  params: {
    frontDoorProfileId: globalInfrastructure.outputs.frontDoorProfileId
    resourceToken: resourceToken
    primaryAppServiceHostname: primaryRegion.outputs.appServiceHostName
    secondaryAppServiceHostname: secondaryRegion.outputs.appServiceHostName
  }
}

// Outputs for the scale unit
@description('Front Door endpoint hostname for global access')
output FRONT_DOOR_ENDPOINT string = 'https://${frontDoorConfig.outputs.frontDoorEndpointHostname}'

@description('Primary region App Service hostname')
output AZURE_PRIMARY_APP_SERVICE string = primaryRegion.outputs.appServiceHostName

@description('Secondary region App Service hostname')
output AZURE_SECONDARY_APP_SERVICE string = secondaryRegion.outputs.appServiceHostName

@description('Global storage account name')
output GLOBAL_STORAGE_ACCOUNT_NAME string = globalInfrastructure.outputs.globalStorageAccountName

@description('Primary resource group name')
output PRIMARY_RESOURCE_GROUP_NAME string = primaryResourceGroup.name

@description('Secondary region resource group name')
output SECONDARY_RESOURCE_GROUP_NAME string = secondaryResourceGroup.name

@description('Global resource group name')
output GLOBAL_RESOURCE_GROUP_NAME string = globalResourceGroup.name

@description('Environment type used for this deployment')
output ENVIRONMENT_TYPE string = envType
