// Global infrastructure module for multi-region scale unit
// This module creates global resources that span multiple regions:
// - Azure Front Door for global load balancing and CDN
// - Global storage account for shared configuration
// - Cross-region monitoring and alerting
//
// Benefits:
// - Single global endpoint for users
// - Automatic failover between regions
// - CDN capabilities for improved performance
// - Centralized configuration management

@description('The primary location for global resources')
param primaryLocation string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Environment type - determines networking configuration')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

var globalTags = union(tags, { 'scale-unit': 'global' })

// Global Private DNS Zone for storage accounts across all regions
resource privateDnsZoneStorage 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: globalTags
}

// Global Front Door profile (endpoints and origins configured separately)
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: '${abbrs.cdnProfiles}global-${resourceToken}'
  location: 'global'
  tags: globalTags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {}
}

// Global Storage Account for shared configuration and metadata
resource globalStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${abbrs.storageStorageAccounts}global${resourceToken}'
  location: primaryLocation
  tags: globalTags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: envType == 'prod' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob service for global storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: globalStorageAccount
  name: 'default'
}

// Container for global configuration
resource globalConfigContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'global-config'
  properties: {
    publicAccess: 'None'
  }
}

// Container for shared application data
resource sharedDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'shared-data'
  properties: {
    publicAccess: 'None'
  }
}

// Outputs
@description('Front Door profile resource ID')
output frontDoorProfileId string = frontDoorProfile.id

@description('Front Door profile Front Door ID for access restrictions')
output frontDoorId string = frontDoorProfile.properties.frontDoorId

@description('Global storage account name')
output globalStorageAccountName string = globalStorageAccount.name

@description('Private DNS Zone ID for storage account')
output privateDnsZoneStorageId string = privateDnsZoneStorage.id
