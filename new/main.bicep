// Created by: Albert Timileyin

targetScope = 'subscription'

// Parameters
@description('Customer name/identifier')
param customerName string

@description('Azure region for deployment')
param location string = 'eastus'

@description('Deployment timestamp')
param deploymentTime string = utcNow('yyyy-MM-dd')

// Variables
var resourceGroupName = '${customerName}-sentinel-rg'
var workspaceName = '${customerName}-sentinel-workspace'
var retentionDays = 90
var workspaceSku = 'PerGB2018'

var defaultTags = {
  Environment: 'Production'
  Project: 'MSSP-Sentinel'
  Customer: customerName
  ManagedBy: 'MSSP'
  Creator: 'Albert Timileyin'
  DeploymentDate: deploymentTime
  TestVersion: 'Infrastructure-Only'
}

// 1. CREATE RESOURCE GROUP
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: defaultTags
}

// 2. LOG ANALYTICS WORKSPACE
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  tags: defaultTags
  scope: resourceGroup
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// 3. MICROSOFT SENTINEL SOLUTION
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspaceName})'
  location: location
  tags: defaultTags
  scope: resourceGroup
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'SecurityInsights(${workspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
}

// 4. SENTINEL ONBOARDING
resource sentinelOnboarding 'Microsoft.OperationalInsights/workspaces/providers/onboardingStates@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/default'
  scope: resourceGroup
  dependsOn: [sentinelSolution]
  properties: {}
}

// 5. AZURE ACTIVITY LOGS
resource azureActivityDataSource 'Microsoft.OperationalInsights/workspaces/dataSources@2020-08-01' = {
  name: '${workspaceName}/AzureActivityLogs'
  scope: resourceGroup
  kind: 'AzureActivityLog'
  properties: {
    linkedResourceId: '/subscriptions/${subscription().subscriptionId}/providers/microsoft.insights/eventtypes/management'
  }
  dependsOn: [logAnalyticsWorkspace]
}

// 6. AZURE AD DATA CONNECTOR
resource aadConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/AzureActiveDirectory'
  scope: resourceGroup
  kind: 'AzureActiveDirectory'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      alerts: { state: 'enabled' }
      signIns: { state: 'enabled' }
      auditLogs: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 7. MICROSOFT DEFENDER XDR
resource defenderXDRConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/MicrosoftThreatProtection'
  scope: resourceGroup
  kind: 'MicrosoftThreatProtection'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      incidents: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// Outputs
output deploymentSummary object = {
  customer: customerName
  resourceGroup: resourceGroupName
  workspace: workspaceName
  location: location
  testVersion: 'Infrastructure-Only'
  infrastructureDeployed: true
  analyticsRulesDeployed: false
  sentinelPortalUrl: 'https://portal.azure.com/#@${subscription().tenantId}/blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
  nextSteps: [
    'Verify Sentinel is enabled'
    'Check data connectors are working'
    'Manually test a few OOTB analytics rules'
    'Then proceed to full automation'
  ]
}
