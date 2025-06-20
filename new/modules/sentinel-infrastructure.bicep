// modules/sentinel-infrastructure.bicep
// Version that avoids conflicts with Microsoft Defender for Cloud

targetScope = 'resourceGroup'

// Parameters
param customerName string
param location string
param workspaceName string
param deploymentTime string
param userAssignedIdentityId string

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

// 1. AUTO-REGISTER REQUIRED PROVIDERS
resource registerProviders 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${customerName}-register-providers'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    azPowerShellVersion: '8.0'
    timeout: 'PT15M'
    retentionInterval: 'PT1H'
    scriptContent: '''
      Write-Host "Starting resource provider registration..."
      
      $providers = @(
          "Microsoft.Insights",
          "Microsoft.SecurityInsights", 
          "Microsoft.OperationalInsights",
          "Microsoft.OperationsManagement"
      )
      
      foreach ($provider in $providers) {
          Write-Host "Registering $provider..."
          Register-AzResourceProvider -ProviderNamespace $provider
      }
      
      # Wait for all providers to be registered
      Write-Host "Waiting for provider registration to complete..."
      $maxWaitTime = 600 # 10 minutes
      $waitTime = 0
      
      do {
          Start-Sleep -Seconds 30
          $waitTime += 30
          
          $allRegistered = $true
          foreach ($provider in $providers) {
              $state = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState
              Write-Host "$provider : $state"
              if ($state -ne "Registered") {
                  $allRegistered = $false
              }
          }
          
          if ($waitTime -ge $maxWaitTime) {
              Write-Host "Timeout waiting for provider registration"
              break
          }
          
      } while (-not $allRegistered)
      
      if ($allRegistered) {
          Write-Host "All resource providers registered successfully!"
      } else {
          Write-Host "Some providers may still be registering, but continuing deployment..."
      }
    '''
  }
}

// 2. Log Analytics Workspace (with unique name to avoid conflicts)
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
  dependsOn: [registerProviders]
}

// 3. Microsoft Sentinel Solution
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

// 4. Sentinel Onboarding
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2022-10-01-preview' = {
  scope: logAnalyticsWorkspace
  name: 'default'
  dependsOn: [sentinelSolution]
  properties: {}
}

// 5. Azure Activity Logs Data Source (should work without conflicts)
resource azureActivityDataSource 'Microsoft.OperationalInsights/workspaces/dataSources@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'AzureActivityLogs'
  kind: 'AzureActivityLog'
  properties: {
    linkedResourceId: '/subscriptions/${subscription().subscriptionId}/providers/microsoft.insights/eventtypes/management'
  }
}

// Skip problematic data connectors that conflict with Defender for Cloud
// These can be configured manually in the portal after deployment

// 6. Basic Data Collection Rules for future use
resource basicSyslogDCR 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
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
}

// 7. Windows Events DCR (basic events, not Security Events)
resource basicWindowsDCR 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${customerName}-Windows-DCR'
  location: location
  tags: defaultTags
  properties: {
    description: 'MSSP Windows Event Collection via AMA'
    dataSources: {
      windowsEventLogs: [
        {
          name: 'System'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'System!*[System[Level=1 or Level=2 or Level=3]]'
          ]
        }
        {
          name: 'Application'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[Level=1 or Level=2 or Level=3]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'WindowsEventsLA'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Event']
        destinations: ['WindowsEventsLA']
      }
    ]
  }
}

// Outputs
output workspaceName string = logAnalyticsWorkspace.name
output workspaceId string = logAnalyticsWorkspace.properties.customerId
output workspaceResourceId string = logAnalyticsWorkspace.id
output syslogDCRId string = basicSyslogDCR.id
output windowsDCRId string = basicWindowsDCR.id
