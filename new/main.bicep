
targetScope = 'subscription'

// Parameters - Only what users need to input
@description('Customer name/identifier (e.g., Customer-001)')
param customerName string

@description('Azure region for deployment')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'francecentral'
  'switzerlandnorth'
  'norwayeast'
  'germanywestcentral'
  'southafricanorth'
  'australiaeast'
  'australiasoutheast'
  'eastasia'
  'southeastasia'
  'japaneast'
  'japanwest'
  'koreacentral'
  'southindia'
  'centralindia'
  'uaenorth'
])
param location string = 'eastus'

@description('Deploy all OOTB analytics rules automatically')
param deployAnalyticsRules bool = true

@description('Deployment timestamp')
param deploymentTime string = utcNow('yyyy-MM-dd')

// Variables
var resourceGroupName = '${customerName}-sentinel-rg'
var workspaceName = '${customerName}-sentinel-workspace'

// 1. AUTO-REGISTER REQUIRED PROVIDERS (Fixed scope)
resource registerProviders 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${customerName}-register-providers'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'SystemAssigned'
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

// 2. CREATE RESOURCE GROUP
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Customer: customerName
    Project: 'MSSP-Sentinel'
    Environment: 'Production'
    ManagedBy: 'MSSP'
    DeploymentDate: deploymentTime
    AutomationLevel: 'Full'
  }
  dependsOn: [registerProviders]
}

// 3. DEPLOY SENTINEL INFRASTRUCTURE
module sentinelInfrastructure 'modules/sentinel-infrastructure.bicep' = {
  name: '${customerName}-sentinel-infrastructure'
  scope: resourceGroup
  params: {
    customerName: customerName
    location: location
    workspaceName: workspaceName
    deploymentTime: deploymentTime
  }
}

// 4. AUTO-DEPLOY ALL OOTB ANALYTICS RULES
module analyticsRules 'modules/analytics-rules-automation.bicep' = if (deployAnalyticsRules) {
  name: '${customerName}-analytics-rules'
  scope: resourceGroup
  params: {
    workspaceName: workspaceName
    customerName: customerName
    location: location
  }
  dependsOn: [sentinelInfrastructure]
}

// Outputs
output deploymentSummary object = {
  customer: customerName
  resourceGroup: resourceGroupName
  workspace: workspaceName
  location: location
  infrastructureDeployed: true
  analyticsRulesDeployed: deployAnalyticsRules
  estimatedRulesCount: deployAnalyticsRules ? '200+' : '0'
  sentinelPortalUrl: 'https://portal.azure.com/#@${tenant().tenantId}/blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
  automationLevel: 'FULL'
  deploymentComplete: true
  nextSteps: deployAnalyticsRules ? [
    'Review deployed analytics rules in Sentinel portal'
    'Associate Data Collection Rules with VMs'
    'Configure threat intelligence feeds'
    'Set up incident assignment rules'
  ] : [
    'Navigate to Sentinel Analytics Rules to enable OOTB rules'
    'Associate Data Collection Rules with VMs'
    'Configure threat intelligence feeds'
  ]
}
