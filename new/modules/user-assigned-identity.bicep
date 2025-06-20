// modules/user-assigned-identity.bicep
// Module to create user-assigned managed identity

targetScope = 'resourceGroup'

param identityName string
param location string
param customerName string

// Create User-Assigned Managed Identity
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    Customer: customerName
    Project: 'MSSP-Sentinel'
    Environment: 'Production'
    ManagedBy: 'MSSP'
    Purpose: 'Deployment-Automation'
  }
}

// Outputs
output identityId string = userAssignedIdentity.id
output principalId string = userAssignedIdentity.properties.principalId
output clientId string = userAssignedIdentity.properties.clientId
