// Parameters - define inputs for deployment
@description('Prefix for all resources')
param prefix string = Sentinel-Auto'

@description('Azure region')
param location string = 'eastus'

@description('Resource tags')
param tags object = {
  Environment: 'Development'
  Project: 'SecEng'
  Owner: 'SecurityTeam'
  CostCenter: 'IT'
}

// Variables - reusable values for the template
var lawName = '${prefix}-law'

// Resources - the Azure resources to be deployed
// Log Analytics Workspace for Sentinel
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Microsoft Sentinel Solution
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${lawName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'SecurityInsights(${lawName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

// Sentinel Onboarding State
resource sentinelOnboardingState 'Microsoft.OperationalInsights/workspaces/providers/onboardingStates@2021-03-01-preview' = {
  name: '${lawName}/Microsoft.SecurityInsights/default'
  location: location
  dependsOn: [
    sentinelSolution
  ]
  properties: {}
}

// Microsoft Threat Protection Data Connector
resource mtpDataConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${lawName}/Microsoft.SecurityInsights/MicrosoftThreatProtection'
  location: location
  kind: 'MicrosoftThreatProtection'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      incidents: {
        state: 'enabled'
      }
    }
  }
  dependsOn: [
    sentinelOnboardingState
  ]
}

// Office 365 Data Connector
resource office365DataConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${lawName}/Microsoft.SecurityInsights/office-365'
  kind: 'Office365'
  location: location
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      exchange: {
        state: 'enabled'
      }
      sharePoint: {
        state: 'enabled'
      }
      teams: {
        state: 'enabled'
      }
    }
  }
  dependsOn: [
    sentinelOnboardingState
  ]
}

// Azure Active Directory Data Connector
resource aadDataConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${lawName}/Microsoft.SecurityInsights/AzureActiveDirectory'
  location: location
  kind: 'AzureActiveDirectory'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      alerts: {
        state: 'enabled'
      }
      signin: {
        state: 'enabled'
      }
      auditLogs: {
        state: 'enabled'
      }
    }
  }
  dependsOn: [
    sentinelOnboardingState
  ]
}

// Azure Activity Log Data Source
resource activityLogDataSource 'Microsoft.OperationalInsights/workspaces/dataSources@2020-08-01' = {
  name: '${lawName}/subscription-${subscription().subscriptionId}'
  kind: 'AzureActivityLog'
  properties: {
    linkedResourceId: '/subscriptions/${subscription().subscriptionId}/providers/microsoft.insights/eventtypes/management'
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

// Outputs - values returned after deployment
@description('Workspace ID for Azure Sentinel')
output sentinelWorkspaceId string = logAnalyticsWorkspace.properties.customerId
