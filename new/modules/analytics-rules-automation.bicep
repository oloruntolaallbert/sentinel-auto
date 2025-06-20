// modules/analytics-rules-automation.bicep
// Fully automated OOTB analytics rules deployment

targetScope = 'resourceGroup'

param workspaceName string
param customerName string
param location string

// Get existing workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  name: workspaceName
}

// AUTOMATED OOTB RULES DEPLOYMENT
resource deployAllOOTBRules 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${customerName}-auto-deploy-ootb-rules'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azPowerShellVersion: '8.0'
    timeout: 'PT45M'
    retentionInterval: 'PT2H'
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
      {
        name: 'CUSTOMER_NAME'
        value: customerName
      }
    ]
    scriptContent: '''
      Write-Host "=========================================="
      Write-Host "AUTOMATED OOTB ANALYTICS RULES DEPLOYMENT"
      Write-Host "=========================================="
      
      $subscriptionId = $env:SUBSCRIPTION_ID
      $resourceGroupName = $env:RESOURCE_GROUP
      $workspaceName = $env:WORKSPACE_NAME
      $customerName = $env:CUSTOMER_NAME
      
      # Connect and set context
      Write-Host "Setting up Azure context..."
      Set-AzContext -SubscriptionId $subscriptionId
      
      # Get access token
      $context = Get-AzContext
      $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, $null, $null, $context.Environment.Endpoints.ResourceManager).AccessToken
      
      $headers = @{
          'Authorization' = "Bearer $token"
          'Content-Type' = 'application/json'
      }
      
      # MSSP Standard Connectors
      $msspConnectors = @(
          "AzureActivity",
          "AzureActiveDirectory", 
          "SecurityEvents",
          "Syslog",
          "MicrosoftThreatProtection",
          "AzureActiveDirectoryIdentityProtection",
          "ThreatIntelligence",
          "Office365",
          "MicrosoftDefenderThreatIntelligence"
      )
      
      Write-Host "MSSP Standard Connectors: $($msspConnectors -join ', ')"
      
      # Function to get all OOTB templates
      function Get-OOTBTemplates {
          $templatesUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRuleTemplates?api-version=2022-10-01-preview"
          
          try {
              Write-Host "Fetching OOTB rule templates..."
              $response = Invoke-RestMethod -Uri $templatesUri -Headers $headers -Method Get
              Write-Host "Found $($response.value.Count) total templates"
              return $response.value
          } catch {
              Write-Host "Error fetching templates: $($_.Exception.Message)"
              return @()
          }
      }
      
      # Function to check if rule should be deployed
      function Should-DeployRule {
          param($template)
          
          # Only deploy Scheduled and NRT rules
          if ($template.kind -ne "Scheduled" -and $template.kind -ne "NRT") {
              return $false
          }
          
          # Check connector requirements
          if ($template.properties.requiredDataConnectors) {
              foreach ($connector in $template.properties.requiredDataConnectors) {
                  if ($connector.connectorId -in $msspConnectors) {
                      return $true
                  }
              }
              return $false
          } else {
              # Deploy generic rules without specific requirements
              return $true
          }
      }
      
      # Function to deploy a single rule
      function Deploy-AnalyticsRule {
          param($template)
          
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
          
          # Add optional properties
          if ($template.properties.entityMappings) {
              $ruleBody.properties.entityMappings = $template.properties.entityMappings
          }
          if ($template.properties.tactics) {
              $ruleBody.properties.tactics = $template.properties.tactics
          }
          if ($template.properties.techniques) {
              $ruleBody.properties.techniques = $template.properties.techniques
          }
          if ($template.properties.customDetails) {
              $ruleBody.properties.customDetails = $template.properties.customDetails
          }
          if ($template.properties.alertDetailsOverride) {
              $ruleBody.properties.alertDetailsOverride = $template.properties.alertDetailsOverride
          }
          
          $createRuleUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRules/$ruleName" + "?api-version=2022-10-01-preview"
          
          try {
              $response = Invoke-RestMethod -Uri $createRuleUri -Headers $headers -Method Put -Body ($ruleBody | ConvertTo-Json -Depth 15)
              Write-Host "✓ SUCCESS: $($template.properties.displayName)" -ForegroundColor Green
              return $true
          } catch {
              Write-Host "✗ FAILED: $($template.properties.displayName) - $($_.Exception.Message)" -ForegroundColor Red
              return $false
          }
      }
      
      # MAIN DEPLOYMENT PROCESS
      Write-Host "`nStarting automated OOTB rules deployment for customer: $customerName"
      Write-Host "Target workspace: $workspaceName"
      
      # Get all templates
      $allTemplates = Get-OOTBTemplates
      if ($allTemplates.Count -eq 0) {
          Write-Host "No templates found. Exiting." -ForegroundColor Red
          exit 1
      }
      
      # Filter templates for MSSP connectors
      $filteredTemplates = @()
      foreach ($template in $allTemplates) {
          if (Should-DeployRule -template $template) {
              $filteredTemplates += $template
          }
      }
      
      Write-Host "`nFiltered to $($filteredTemplates.Count) rules for MSSP connectors"
      
      # Deploy rules in batches
      $deployedCount = 0
      $failedCount = 0
      $batchSize = 10
      $totalBatches = [Math]::Ceiling($filteredTemplates.Count / $batchSize)
      
      for ($batch = 0; $batch -lt $totalBatches; $batch++) {
          $startIndex = $batch * $batchSize
          $endIndex = [Math]::Min(($batch + 1) * $batchSize - 1, $filteredTemplates.Count - 1)
          
          Write-Host "`n--- BATCH $($batch + 1)/$totalBatches (Rules $($startIndex + 1)-$($endIndex + 1)) ---"
          
          for ($i = $startIndex; $i -le $endIndex; $i++) {
              $template = $filteredTemplates[$i]
              if (Deploy-AnalyticsRule -template $template) {
                  $deployedCount++
              } else {
                  $failedCount++
              }
              
              # Small delay to avoid rate limiting
              Start-Sleep -Milliseconds 500
          }
          
          # Longer pause between batches
          if ($batch -lt $totalBatches - 1) {
              Write-Host "Pausing between batches..."
              Start-Sleep -Seconds 5
          }
      }
      
      # FINAL SUMMARY
      Write-Host "`n=========================================="
      Write-Host "DEPLOYMENT COMPLETED!"
      Write-Host "=========================================="
      Write-Host "Customer: $customerName"
      Write-Host "Workspace: $workspaceName"
      Write-Host "Total Templates Found: $($allTemplates.Count)"
      Write-Host "MSSP-Relevant Templates: $($filteredTemplates.Count)"
      Write-Host "Successfully Deployed: $deployedCount" -ForegroundColor Green
      Write-Host "Failed Deployments: $failedCount" -ForegroundColor Red
      Write-Host "Success Rate: $([Math]::Round(($deployedCount / $filteredTemplates.Count) * 100, 1))%"
      Write-Host "=========================================="
      
      if ($deployedCount -gt 0) {
          Write-Host "✓ OOTB Analytics Rules deployment completed successfully!" -ForegroundColor Green
      } else {
          Write-Host "✗ No rules were deployed. Check errors above." -ForegroundColor Red
          exit 1
      }
    '''
  }
}

output rulesDeploymentResult object = {
  deploymentName: deployAllOOTBRules.name
  status: 'Completed'
  automationType: 'Full OOTB Deployment'
  targetWorkspace: workspaceName
}
