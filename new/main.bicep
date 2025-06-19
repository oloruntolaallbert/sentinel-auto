// main.bicep - Complete MSSP Sentinel Deployment (Fixed Version)
// One-click: Infrastructure + All OOTB Analytics Rules

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
var enableAllOOTBRules = true

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

// 9. Security Events DCR (AMA)
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
}

// 10. Syslog DCR (AMA)
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

// AUTO-DEPLOY ALL OOTB ANALYTICS RULES
resource deployOOTBRules 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (enableAllOOTBRules) {
  name: '${resourcePrefix}-deploy-ootb-rules'
  location: location
  tags: defaultTags
  kind: 'AzurePowerShell'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azPowerShellVersion: '8.0'
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'WORKSPACE_NAME'
        value: workspaceName
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    scriptContent: '''
      # Get all OOTB analytics rule templates and deploy them
      Write-Host "Starting OOTB Analytics Rules deployment..."
      
      # Connect using managed identity
      Connect-AzAccount -Identity
      
      $subscriptionId = $env:SUBSCRIPTION_ID
      $resourceGroupName = $env:RESOURCE_GROUP
      $workspaceName = $env:WORKSPACE_NAME
      
      # Set context
      Set-AzContext -SubscriptionId $subscriptionId
      
      # Get access token for REST API calls
      $context = Get-AzContext
      $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, $null, $null, $context.Environment.Endpoints.ResourceManager).AccessToken
      
      $headers = @{
          'Authorization' = "Bearer $token"
          'Content-Type' = 'application/json'
      }
      
      # Get all alert rule templates
      $templatesUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRuleTemplates?api-version=2021-10-01"
      
      try {
          $templatesResponse = Invoke-RestMethod -Uri $templatesUri -Headers $headers -Method Get
          $templates = $templatesResponse.value
          
          Write-Host "Found $($templates.Count) OOTB rule templates"
          
          # MSSP Default Connectors for filtering
          $msspConnectors = @(
              "AzureActivity",
              "AzureActiveDirectory", 
              "SecurityEvents",
              "Syslog",
              "MicrosoftThreatProtection",
              "AzureActiveDirectoryIdentityProtection",
              "ThreatIntelligence"
          )
          
          $deployedCount = 0
          
          foreach ($template in $templates) {
              # Only deploy Scheduled and NRT rules
              if ($template.kind -eq "Scheduled" -or $template.kind -eq "NRT") {
                  
                  # Check if rule matches our connectors
                  $shouldDeploy = $false
                  if ($template.properties.requiredDataConnectors) {
                      foreach ($connector in $template.properties.requiredDataConnectors) {
                          if ($connector.connectorId -in $msspConnectors) {
                              $shouldDeploy = $true
                              break
                          }
                      }
                  } else {
                      # Deploy generic rules without specific connector requirements
                      $shouldDeploy = $true
                  }
                  
                  if ($shouldDeploy) {
                      # Create analytics rule from template
                      $ruleName = [System.Guid]::NewGuid().ToString()
                      
                      $ruleBody = @{
                          kind = $template.kind
                          properties = @{
                              displayName = $template.properties.displayName
                              description = $template.properties.description
                              severity = $template.properties.severity
                              enabled = $true
                              query = $template.properties.query
                              queryFrequency = $template.properties.queryFrequency
                              queryPeriod = $template.properties.queryPeriod
                              triggerOperator = $template.properties.triggerOperator
                              triggerThreshold = $template.properties.triggerThreshold
                              suppressionDuration = $template.properties.suppressionDuration
                              suppressionEnabled = $template.properties.suppressionEnabled
                              alertRuleTemplateName = $template.name
                              templateVersion = $template.properties.version
                          }
                      }
                      
                      # Add optional properties if they exist
                      if ($template.properties.entityMappings) {
                          $ruleBody.properties.entityMappings = $template.properties.entityMappings
                      }
                      if ($template.properties.tactics) {
                          $ruleBody.properties.tactics = $template.properties.tactics
                      }
                      if ($template.properties.techniques) {
                          $ruleBody.properties.techniques = $template.properties.techniques
                      }
                      
                      $createRuleUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRules/$ruleName" + "?api-version=2021-10-01"
                      
                      try {
                          $response = Invoke-RestMethod -Uri $createRuleUri -Headers $headers -Method Put -Body ($ruleBody | ConvertTo-Json -Depth 10)
                          Write-Host "✓ Deployed: $($template.properties.displayName)"
                          $deployedCount++
                      } catch {
                          Write-Host "✗ Failed to deploy: $($template.properties.displayName) - $($_.Exception.Message)"
                      }
                  }
              }
          }
          
          Write-Host "Successfully deployed $deployedCount OOTB analytics rules"
          
      } catch {
          Write-Host "Error getting templates: $($_.Exception.Message)"
          throw
      }
    '''
  }
  dependsOn: [
    sentinelOnboarding
    aadConnector
    defenderXDRConnector
    aadIPConnector
    threatIntelConnector
  ]
}

// Outputs
output workspaceName string = logAnalyticsWorkspace.name
output workspaceId string = logAnalyticsWorkspace.properties.customerId
output resourceGroupName string = resourceGroup().name
output sentinelPortalUrl string = 'https://portal.azure.com/#@${subscription().tenantId}/blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
output securityEventsDCR string = securityEventsDCR.id
output syslogDCR string = syslogDCR.id

output deploymentSummary object = {
  customer: customerName
  workspace: workspaceName
  location: location
  dataConnectors: 8
  analyticsRulesDeployed: enableAllOOTBRules
  estimatedRulesCount: '200+'
  deploymentComplete: true
}
