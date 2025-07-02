// Monitoring infrastructure module for application observability
// This module creates monitoring and observability resources:
// 1. Log Analytics Workspace for centralized logging
// 2. Application Insights for application performance monitoring
// 3. Application Insights Dashboard for visualization
//
// Observability Benefits:
// - Centralized logging and metrics collection
// - Application performance monitoring and diagnostics
// - Custom dashboards for operational insights
// - Integration with Azure Monitor ecosystem

@description('The location used for all deployed resources')
param location string

@description('Tags that will be applied to all resources')
param tags object = {}

@description('Abbreviations for Azure resource naming')
param abbrs object

@description('Unique token for resource naming')
param resourceToken string

@description('Environment type')
@allowed(['dev', 'test', 'prod'])
param envType string = 'dev'

@description('Enable telemetry for the modules')
param enableTelemetry bool = true

// Define resource names
var logAnalyticsName = '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
var applicationInsightsName = '${abbrs.insightsComponents}${resourceToken}'
var applicationInsightsDashboardName = '${abbrs.portalDashboards}${resourceToken}'

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.7.0' = {
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    dataRetention: 30
    enableTelemetry: enableTelemetry
  }
}

module applicationInsights 'br/public:avm/res/insights/component:0.4.1' = {
  params: {
    name: applicationInsightsName
    location: location
    tags: tags
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: logAnalytics.outputs.resourceId
    enableTelemetry: enableTelemetry
  }
}

module applicationInsightsDashboard 'modules/applicationinsights-dashboard.bicep' = if (envType == 'prod') {
  // name: 'dashboard-deployment'
  params: {
    name: applicationInsightsDashboardName
    location: location
    applicationInsightsName: applicationInsights.outputs.name
    applicationInsightsResourceId: applicationInsights.outputs.resourceId
  }
}

// Outputs for use by other modules
@description('Application Insights resource ID')
output applicationInsightsResourceId string = applicationInsights.outputs.resourceId

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.outputs.connectionString

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.outputs.instrumentationKey

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceResourceId string = logAnalytics.outputs.resourceId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.name

@description('Application Insights dashboard resource ID')
output dashboardResourceId string = envType == 'prod' ? applicationInsightsDashboard.outputs.dashboardResourceId : ''
