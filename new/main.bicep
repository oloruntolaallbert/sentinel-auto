// main.bicep - MSSP Sentinel Infrastructure Deployment
// One-click infrastructure deployment with all connectors

targetScope = 'resourceGroup'

// Parameters - only what's needed for one-click
@description('Customer name/identifier')
param customerName string

@description('Azure region')
param location string = resourceGroup().location

@description('Deployment timestamp')
param deploymentTime string = utcNow('yyyy-MM-dd')

// Variables
var workspaceName = '${customerName}-sentinel-workspace'
var resourcePrefix = customerName

// MSSP Standard Settings
var retentionDays = 90
var workspaceSku = 'PerGB2018'

// MSSP Standard Tags
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
resource sentinelOnboarding 'Microsoft.OperationalInsights/workspaces/providers/onboardingStates@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/default'
  scope: logAnalyticsWorkspace
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
resource aadConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/AzureActiveDirectory'
  scope: logAnalyticsWorkspace
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
resource defenderXDRConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/MicrosoftThreatProtection'
  scope: logAnalyticsWorkspace
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
resource aadIPConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/AADIdentityProtection'
  scope: logAnalyticsWorkspace
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
resource threatIntelConnector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/ThreatIntelligence'
  scope: logAnalyticsWorkspace
  kind: 'ThreatIntelligence'
  properties: {
    tenantId: subscription().tenantId
    dataTypes: {
      indicators: { state: 'enabled' }
    }
  }
  dependsOn: [sentinelOnboarding]
}

// 9. Office 365 Data Connector (added to complete MSSP set)
resource office365Connector 'Microsoft.OperationalInsights/workspaces/providers/dataConnectors@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/Office365'
  scope: logAnalyticsWorkspace
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

// 10. Security Events DCR (AMA)
resource securityEventsDCR 'Microsoft.Insights/dataCollectionRules@2021-09-01-preview' = {
  name: '${resourcePrefix}-SecurityEvents-DCR'
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
            'Security!*[System[(EventID=4624 or EventID=4625 or EventID=4648 or EventID=4688 or EventID=4720 or EventID=4726 or EventID=4776 or EventID=4782 or EventID=4793)]]'
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
}

// 11. Syslog DCR (AMA)
resource syslogDCR 'Microsoft.Insights/dataCollectionRules@2021-09-01-preview' = {
  name: '${resourcePrefix}-Syslog-DCR'
  location: location
  tags: defaultTags
  properties: {
    description: 'MSSP Syslog Collection via AMA'
    dataSources: {
      syslog: [
        {
          name: 'SyslogData'
          streams: ['Microsoft-Syslog']
          facilityNames: ['auth', 'authpriv', 'cron', 'daemon', 'kern', 'local0', 'local1', 'local2', 'local3', 'local4', 'local5', 'local6', 'local7', 'lpr', 'mail', 'news', 'syslog', 'user', 'uucp']
          logLevels: ['Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency']
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
}

// 12. MSSP Standard Watchlist for Threat Intelligence
resource msspWatchlist 'Microsoft.OperationalInsights/workspaces/providers/watchlists@2021-03-01-preview' = {
  name: '${workspaceName}/Microsoft.SecurityInsights/MSSP-ThreatIntel'
  scope: logAnalyticsWorkspace
  properties: {
    displayName: 'MSSP Threat Intelligence'
    provider: 'MSSP Security Team'
    source: 'Internal'
    description: 'High-risk indicators identified across MSSP customer base'
    numberOfLinesToSkip: 0
    rawContent: 'Indicator,Type,Description,Confidence,TLP\n192.0.2.100,IP,Known malware C2,High,GREEN\n203.0.113.50,IP,Suspicious scanning activity,Medium,GREEN\nmalware.example.com,Domain,Malicious domain,High,GREEN'
    itemsSearchKey: 'Indicator'
    contentType: 'text/csv'
  }
  dependsOn: [sentinelOnboarding]
}

// Outputs
output workspaceName string = logAnalyticsWorkspace.name
output workspaceId string = logAnalyticsWorkspace.properties.customerId
output workspaceResourceId string = logAnalyticsWorkspace.id
output resourceGroupName string = resourceGroup().name
output sentinelPortalUrl string = 'https://portal.azure.com/#@${subscription().tenantId}/blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
output securityEventsDCRId string = securityEventsDCR.id
output syslogDCRId string = syslogDCR.id

output deploymentSummary object = {
  customer: customerName
  workspace: workspaceName
  location: location
  dataConnectorsDeployed: 9
  infrastructureComplete: true
  nextSteps: [
    'Navigate to Sentinel Analytics Rules in the portal'
    'Use "Rule templates" to bulk-enable OOTB rules for enabled connectors'
    'Associate Security Events DCR with Windows VMs'
    'Associate Syslog DCR with Linux VMs'
    'Configure TAXII threat intelligence feeds'
  ]
}
