// Front Door configuration module for multi-region load balancing
// This module configures Front Door endpoints, origin groups, and routing
// It must be deployed after the App Services are created to use their hostnames

@description('Front Door profile resource ID')
param frontDoorProfileId string

@description('Unique token for resource naming')
param resourceToken string

@description('Primary App Service hostname')
param primaryAppServiceHostname string

@description('Secondary App Service hostname')
param secondaryAppServiceHostname string

// Reference to existing Front Door profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' existing = {
  name: last(split(frontDoorProfileId, '/'))
}

// Front Door endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: 'app-${resourceToken}'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin group for the App Services
resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'app-services'
  properties: {
    loadBalancingSettings: {
      sampleSize: 2 // Originally 4
      successfulSamplesRequired: 2 // Originally 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 15 // Originally 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// Primary region origin - Equal weight routing
resource primaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: frontDoorOriginGroup
  name: 'primary-app-service'
  properties: {
    hostName: primaryAppServiceHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: primaryAppServiceHostname
    priority: 1
    weight: 500
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Secondary region origin - Equal weight routing
resource secondaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: frontDoorOriginGroup
  name: 'secondary-app-service'
  properties: {
    hostName: secondaryAppServiceHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: secondaryAppServiceHostname
    priority: 1
    weight: 500
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Routing rule for the application
resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: frontDoorEndpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    primaryOrigin
    secondaryOrigin
  ]
}

// Outputs
@description('Front Door endpoint hostname')
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName
