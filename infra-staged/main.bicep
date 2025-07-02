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

@description('Location')
param location string

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

// Tags that should be applied to all resources.
var tags = {
  'azd-env-name': environmentName
  'environment-type': envType
  'scale-unit': 'multi-region'
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, environmentName, primaryLocation)

// Create resource group for all resources
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: 'rg-${environmentName}-primary'
//   location: primaryLocation
//   tags: union(tags, { 'region-role': 'primary' })
// }

// resource secondaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: 'rg-${environmentName}-secondary'
//   location: secondaryLocation
//   tags: union(tags, { 'region-role': 'secondary' })
// }

// resource globalResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
//   name: 'rg-${environmentName}-global'
//   location: primaryLocation
//   tags: union(tags, { 'region-role': 'global' })
// }

// Deploy global infrastructure (Front Door profile, global storage, DNS zones)
module globalInfrastructure './global/main.bicep' = {
  name: 'globalInfrastructureDeployment'
  scope: resourceGroup
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
  scope: resourceGroup
  params: {
    location: primaryLocation
    tags: union(tags, { 'region-role': 'primary' })
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    regionSuffix: 'primary'
    privateDnsZoneStorageId: globalInfrastructure.outputs.privateDnsZoneStorageId
    frontDoorId: globalInfrastructure.outputs.frontDoorId
  }
}

// Deploy secondary region infrastructure
module secondaryRegion './regional/main.bicep' = {
  name: 'secondaryRegionDeployment'
  scope: resourceGroup
  params: {
    location: secondaryLocation
    tags: union(tags, { 'region-role': 'secondary' })
    envType: envType
    abbrs: abbrs
    resourceToken: resourceToken
    regionSuffix: 'secondary'
    privateDnsZoneStorageId: globalInfrastructure.outputs.privateDnsZoneStorageId
    frontDoorId: globalInfrastructure.outputs.frontDoorId
  }
}

// Configure Front Door endpoints and origins after App Services are created
module frontDoorConfig './global/front-door-config.bicep' = {
  name: 'frontDoorConfigDeployment'
  scope: resourceGroup
  params: {
    frontDoorProfileId: globalInfrastructure.outputs.frontDoorProfileId
    resourceToken: resourceToken
    primaryAppServiceHostname: primaryRegion.outputs.appServiceHostName
    secondaryAppServiceHostname: secondaryRegion.outputs.appServiceHostName
  }
}

// Outputs for the scale unit
@description('Front Door endpoint hostname for global access')
output FRONT_DOOR_ENDPOINT string = frontDoorConfig.outputs.frontDoorEndpointHostname

@description('Primary region App Service hostname')
output AZURE_PRIMARY_APP_SERVICE string = primaryRegion.outputs.appServiceHostName

@description('Secondary region App Service hostname')
output AZURE_SECONDARY_APP_SERVICE string = secondaryRegion.outputs.appServiceHostName

@description('Global storage account name')
output globalStorageAccountName string = globalInfrastructure.outputs.globalStorageAccountName

@description('Resource group name')
output resourceGroupName string = resourceGroup.name

// @description('Secondary region resource group name')
// output secondaryResourceGroupName string = secondaryResourceGroup.name

// @description('Global resource group name')
// output globalResourceGroupName string = globalResourceGroup.name

@description('Environment type used for this deployment')
output environmentType string = envType
