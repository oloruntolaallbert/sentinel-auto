// modules/sentinel-infrastructure.bicep
// Place this in: /new/modules/sentinel-infrastructure.bicep

targetScope = 'resourceGroup'

// Parameters
param customerName string
param location string
param workspaceName string
param deploymentTime string

// Variables
var retentionDays = 90
var workspaceSku = 'PerGB2018'

var defaultTags = {
  Environment: 'Production'
  Project: 'MSSP-Sentinel'
  Customer: customerName
  ManagedBy: 'MSSP'
  DeploymentDate: deploymentTime
}

// 1. Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: workspaceName
  location: location
  tags: defaultTags
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

// 2. Microsoft Sentinel Solution
resource sentinelSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspaceName})'
  location: location
  tags: defaultTags
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

// 3. Sentinel Onboarding
resource sentinelOnboarding 'Microsoft.OperationalInsights/workspaces/providers/onboardingStates@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/default'
  dependsOn: [sentinelSolution]
  properties: {}
}

// 4. Azure Activity Logs Data Source
resource azureActivityDataSource 'Microsoft.OperationalInsights/workspaces/dataSources@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'AzureActivityLogs'
  kind: 'AzureActivityLog'
  properties: {
    linkedResourceId: '/subscriptions/${subscription().subscriptionId}/providers/microsoft.insights/eventtypes/management'
  }
}

// 5. Azure AD Data Connector
resource aadConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/AzureActiveDirectory'
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

// 6. Microsoft Defender XDR
resource defenderXDRConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/MicrosoftThreatProtection'
  kind: 'MicrosoftThreatProtection'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      incidents: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 7. Azure AD Identity Protection
resource aadIPConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/AADIdentityProtection'
  kind: 'AzureActiveDirectoryIdentityProtection'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      alerts: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 8. Threat Intelligence
resource threatIntelConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/ThreatIntelligence'
  kind: 'ThreatIntelligence'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      indicators: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 9. Office 365 Data Connector
resource office365Connector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2022-10-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/Office365'
  kind: 'Office365'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      exchange: { state: 'enabled' }
      sharePoint: { state: 'enabled' }
      teams: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 10. Create SecurityEvent Table
resource securityEventTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: 'SecurityEvent'
  properties: {
    retentionInDays: retentionDays
    plan: 'Analytics'
  }
}

// 11. Create Syslog Table
resource syslogTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: 'Syslog'
  properties: {
    retentionInDays: retentionDays
    plan: 'Analytics'
  }
}

// 12. Security Events DCR
resource securityEventsDCR 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${customerName}-SecurityEvents-DCR'
  location: location
  tags: defaultTags
  properties: {
    description: 'MSSP Security Events Collection via AMA'
    dataSources: {
      windowsEventLogs: [
        {
          name: 'SecurityEvents'
          streams: ['Microsoft-SecurityEvent']
          xPathQueries: [
            'Security!*[System[(EventID=4624 or EventID=4625 or EventID=4648 or EventID=4688 or EventID=4720 or EventID=4726 or EventID=4776)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'SecurityEventsLA'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-SecurityEvent']
        destinations: ['SecurityEventsLA']
      }
    ]
  }
  dependsOn: [securityEventTable]
}

// 13. Syslog DCR
resource syslogDCR 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${customerName}-Syslog-DCR'
  location: location
  tags: defaultTags
  properties: {
    description: 'MSSP Syslog Collection via AMA'
    dataSources: {
      syslog: [
        {
          name: 'SyslogData'
          streams: ['Microsoft-Syslog']
          facilityNames: ['auth', 'authpriv', 'daemon', 'kern', 'syslog', 'user']
          logLevels: ['Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'SyslogLA'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Syslog']
        destinations: ['SyslogLA']
      }
    ]
  }
  dependsOn: [syslogTable]
}

// Outputs
output workspaceName string = logAnalyticsWorkspace.name
output workspaceId string = logAnalyticsWorkspace.properties.customerId
output workspaceResourceId string = logAnalyticsWorkspace.id
output securityEventsDCRId string = securityEventsDCR.id
output syslogDCRId string = syslogDCR.id
