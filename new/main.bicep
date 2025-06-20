// Created by: Albert Timileyin

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
var userAssignedIdentityName = '${customerName}-deployment-identity'

// 1. CREATE RESOURCE GROUP
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Customer: customerName
    Project: 'MSSP-Sentinel'
    Environment: 'Production'
    ManagedBy: 'MSSP'
    Creator: 'Albert Timileyin'
    DeploymentDate: deploymentTime
    AutomationLevel: 'Full'
  }
}

// 2. CREATE USER-ASSIGNED MANAGED IDENTITY MODULE
module userAssignedIdentityModule 'modules/user-assigned-identity.bicep' = {
  name: '${customerName}-identity-module'
  scope: resourceGroup
  params: {
    identityName: userAssignedIdentityName
    location: location
    customerName: customerName
  }
}

// 3. ASSIGN CONTRIBUTOR ROLE TO MANAGED IDENTITY
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, 'contributor', userAssignedIdentityName)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalType: 'ServicePrincipal'
    principalId: userAssignedIdentityModule.outputs.principalId
  }
}

// 4. ASSIGN SENTINEL CONTRIBUTOR ROLE TO MANAGED IDENTITY
resource sentinelContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, 'sentinel-contributor', userAssignedIdentityName)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ab8e14d6-4a74-4a29-9ba8-549422addade') // Sentinel Contributor
    principalType: 'ServicePrincipal'
    principalId: userAssignedIdentityModule.outputs.principalId
  }
}
// 4b. ASSIGN LOG ANALYTICS CONTRIBUTOR ROLE TO MANAGED IDENTITY
resource logAnalyticsContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, 'log-analytics-contributor', userAssignedIdentityName)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalType: 'ServicePrincipal'
    principalId: userAssignedIdentityModule.outputs.principalId
  }
}

// 5. DEPLOY SENTINEL INFRASTRUCTURE
module sentinelInfrastructure 'modules/sentinel-infrastructure.bicep' = {
  name: '${customerName}-sentinel-infrastructure'
  scope: resourceGroup
  params: {
    customerName: customerName
    location: location
    workspaceName: workspaceName
    deploymentTime: deploymentTime
    userAssignedIdentityId: userAssignedIdentityModule.outputs.identityId
  }
  dependsOn: [contributorRoleAssignment]
}

// 6. AUTO-DEPLOY ALL OOTB ANALYTICS RULES
module analyticsRules 'modules/analytics-rules-automation.bicep' = if (deployAnalyticsRules) {
  name: '${customerName}-analytics-rules'
  scope: resourceGroup
  params: {
    workspaceName: workspaceName
    customerName: customerName
    location: location
    userAssignedIdentityId: userAssignedIdentityModule.outputs.identityId
  }
  dependsOn: [sentinelInfrastructure, sentinelContributorRoleAssignment]
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
