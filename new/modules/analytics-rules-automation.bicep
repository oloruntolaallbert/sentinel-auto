// modules/analytics-rules-automation.bicep
// Updated for UserAssigned identity

targetScope = 'resourceGroup'

param workspaceName string
param customerName string
param location string
param userAssignedIdentityId string

// AUTOMATED OOTB RULES DEPLOYMENT
resource deployAllOOTBRules 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${customerName}-auto-deploy-ootb-rules'
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
      
      # Enhanced error handling function
      function Handle-Error {
          param($ErrorMessage, $IsCritical = $false)
          Write-Host "ERROR: $ErrorMessage" -ForegroundColor Red
          if ($IsCritical) {
              Write-Host "Critical error encountered. Exiting deployment." -ForegroundColor Red
              exit 1
          }
      }
      
      # Wait for permissions to propagate
      Write-Host "Waiting for permissions to propagate..."
      Start-Sleep -Seconds 60
      
      # Connect and set context
      try {
          Write-Host "Setting up Azure context..."
          Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
      } catch {
          Handle-Error "Failed to set Azure context: $($_.Exception.Message)" $true
      }
      
      # Get access token with retry logic
      $maxRetries = 3
      $retryCount = 0
      $token = $null
      
      while ($retryCount -lt $maxRetries -and -not $token) {
          try {
              $context = Get-AzContext
              $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
                  $context.Account, 
                  $context.Environment, 
                  $context.Tenant.Id, 
                  $null, 
                  $null, 
                  $null, 
                  $context.Environment.Endpoints.ResourceManager
              ).AccessToken
          } catch {
              $retryCount++
              if ($retryCount -ge $maxRetries) {
                  Handle-Error "Failed to get access token after $maxRetries attempts: $($_.Exception.Message)" $true
              }
              Write-Host "Retrying token acquisition ($retryCount/$maxRetries)..."
              Start-Sleep -Seconds 5
          }
      }
      
      $headers = @{
          'Authorization' = "Bearer $token"
          'Content-Type' = 'application/json'
      }
      
      # MSSP Standard Connectors - Enhanced list
      $msspConnectors = @(
          "AzureActivity",
          "AzureActiveDirectory", 
          "SecurityEvents",
          "Syslog",
          "MicrosoftThreatProtection",
          "AzureActiveDirectoryIdentityProtection",
          "ThreatIntelligence",
          "Office365",
          "MicrosoftDefenderThreatIntelligence",
          "MicrosoftCloudAppSecurity",
          "AzureSecurityCenter",
          "MicrosoftDefenderAdvancedThreatProtection"
      )
      
      Write-Host "MSSP Standard Connectors: $($msspConnectors -join ', ')"
      
      # Function to get all OOTB templates with retry
      function Get-OOTBTemplates {
          $templatesUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRuleTemplates?api-version=2022-10-01-preview"
          
          $maxRetries = 3
          $retryCount = 0
          
          while ($retryCount -lt $maxRetries) {
              try {
                  Write-Host "Fetching OOTB rule templates (attempt $($retryCount + 1))..."
                  $response = Invoke-RestMethod -Uri $templatesUri -Headers $headers -Method Get -ErrorAction Stop
                  Write-Host "Found $($response.value.Count) total templates" -ForegroundColor Green
                  return $response.value
              } catch {
                  $retryCount++
                  if ($retryCount -ge $maxRetries) {
                      Handle-Error "Failed to fetch templates after $maxRetries attempts: $($_.Exception.Message)" $true
                  }
                  Write-Host "Retrying template fetch..."
                  Start-Sleep -Seconds 5
              }
          }
      }
      
      # Function to check if rule should be deployed
      function Should-DeployRule {
          param($template)
          
          # Only deploy Scheduled and NRT rules
          if ($template.kind -ne "Scheduled" -and $template.kind -ne "NRT") {
              return $false
          }
          
          # Skip if no query
          if (-not $template.properties.query -or $template.properties.query.Trim() -eq "") {
              return $false
          }
          
          # Check connector requirements
          if ($template.properties.requiredDataConnectors -and $template.properties.requiredDataConnectors.Count -gt 0) {
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
      
      # Function to deploy a single rule with enhanced error handling
      function Deploy-AnalyticsRule {
          param($template, $retryOnFailure = $true)
          
          $ruleName = [System.Guid]::NewGuid().ToString()
          
          # Build rule body with validation
          $ruleBody = @{
              kind = $template.kind
              properties = @{
                  displayName = $template.properties.displayName
                  description = if ($template.properties.description) { $template.properties.description } else { "MSSP Auto-deployed rule" }
                  severity = if ($template.properties.severity) { $template.properties.severity } else { "Medium" }
                  enabled = $true
                  query = $template.properties.query
                  queryFrequency = $template.properties.queryFrequency
                  queryPeriod = $template.properties.queryPeriod
                  triggerOperator = $template.properties.triggerOperator
                  triggerThreshold = $template.properties.triggerThreshold
                  suppressionDuration = if ($template.properties.suppressionDuration) { $template.properties.suppressionDuration } else { "PT5H" }
                  suppressionEnabled = if ($null -ne $template.properties.suppressionEnabled) { $template.properties.suppressionEnabled } else { $false }
                  alertRuleTemplateName = $template.name
                  templateVersion = if ($template.properties.version) { $template.properties.version } else { "1.0.0" }
              }
          }
          
          # Add optional properties safely
          if ($template.properties.entityMappings -and $template.properties.entityMappings.Count -gt 0) {
              $ruleBody.properties.entityMappings = $template.properties.entityMappings
          }
          if ($template.properties.tactics -and $template.properties.tactics.Count -gt 0) {
              $ruleBody.properties.tactics = $template.properties.tactics
          }
          if ($template.properties.techniques -and $template.properties.techniques.Count -gt 0) {
              $ruleBody.properties.techniques = $template.properties.techniques
          }
          if ($template.properties.customDetails) {
              $ruleBody.properties.customDetails = $template.properties.customDetails
          }
          if ($template.properties.alertDetailsOverride) {
              $ruleBody.properties.alertDetailsOverride = $template.properties.alertDetailsOverride
          }
          if ($template.properties.eventGroupingSettings) {
              $ruleBody.properties.eventGroupingSettings = $template.properties.eventGroupingSettings
          }
          
          $createRuleUri = "$($context.Environment.Endpoints.ResourceManager)subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRules/$ruleName" + "?api-version=2022-10-01-preview"
          
          $maxRetries = if ($retryOnFailure) { 2 } else { 1 }
          $retryCount = 0
          
          while ($retryCount -lt $maxRetries) {
              try {
                  $response = Invoke-RestMethod -Uri $createRuleUri -Headers $headers -Method Put -Body ($ruleBody | ConvertTo-Json -Depth 15) -ErrorAction Stop
                  Write-Host "✓ SUCCESS: $($template.properties.displayName)" -ForegroundColor Green
                  return $true
              } catch {
                  $retryCount++
                  $errorMessage = $_.Exception.Message
                  
                  # Check for specific errors
                  if ($errorMessage -match "BadRequest" -or $errorMessage -match "InvalidTemplate") {
                      Write-Host "✗ SKIPPED (Invalid): $($template.properties.displayName)" -ForegroundColor Yellow
                      return $false
                  }
                  
                  if ($retryCount -ge $maxRetries) {
                      Write-Host "✗ FAILED: $($template.properties.displayName) - $errorMessage" -ForegroundColor Red
                      return $false
                  }
                  
                  Write-Host "Retrying rule deployment for: $($template.properties.displayName)"
                  Start-Sleep -Seconds 2
              }
          }
          
          return $false
      }
      
      # MAIN DEPLOYMENT PROCESS
      Write-Host "`nStarting automated OOTB rules deployment for customer: $customerName"
      Write-Host "Target workspace: $workspaceName"
      
      # Get all templates
      $allTemplates = Get-OOTBTemplates
      if ($allTemplates.Count -eq 0) {
          Handle-Error "No templates found. Exiting." $true
      }
      
      # Filter templates for MSSP connectors
      Write-Host "`nFiltering templates for MSSP connectors..."
      $filteredTemplates = @()
      $skippedReasons = @{
          "WrongKind" = 0
          "NoConnectorMatch" = 0
          "NoQuery" = 0
      }
      
      foreach ($template in $allTemplates) {
          if ($template.kind -ne "Scheduled" -and $template.kind -ne "NRT") {
              $skippedReasons["WrongKind"]++
          } elseif (-not $template.properties.query -or $template.properties.query.Trim() -eq "") {
              $skippedReasons["NoQuery"]++
          } elseif (Should-DeployRule -template $template) {
              $filteredTemplates += $template
          } else {
              $skippedReasons["NoConnectorMatch"]++
          }
      }
      
      Write-Host "`nTemplate Analysis:"
      Write-Host "- Total templates: $($allTemplates.Count)"
      Write-Host "- MSSP-relevant: $($filteredTemplates.Count)"
      Write-Host "- Skipped (wrong kind): $($skippedReasons['WrongKind'])"
      Write-Host "- Skipped (no query): $($skippedReasons['NoQuery'])"
      Write-Host "- Skipped (connector mismatch): $($skippedReasons['NoConnectorMatch'])"
      
      if ($filteredTemplates.Count -eq 0) {
          Handle-Error "No templates match MSSP connector requirements" $true
      }
      
      # Deploy rules in batches with progress tracking
      $deployedCount = 0
      $failedCount = 0
      $skippedCount = 0
      $batchSize = 10
      $totalBatches = [Math]::Ceiling($filteredTemplates.Count / $batchSize)
      
      # Track deployment details
      $deploymentResults = @{
          "Successful" = @()
          "Failed" = @()
          "Skipped" = @()
      }
      
      for ($batch = 0; $batch -lt $totalBatches; $batch++) {
          $startIndex = $batch * $batchSize
          $endIndex = [Math]::Min(($batch + 1) * $batchSize - 1, $filteredTemplates.Count - 1)
          
          Write-Host "`n--- BATCH $($batch + 1)/$totalBatches (Rules $($startIndex + 1)-$($endIndex + 1)) ---"
          $batchProgress = 0
          
          for ($i = $startIndex; $i -le $endIndex; $i++) {
              $template = $filteredTemplates[$i]
              $batchProgress++
              
              Write-Host "[$batchProgress/$($endIndex - $startIndex + 1)] Deploying: $($template.properties.displayName)"
              
              $result = Deploy-AnalyticsRule -template $template
              
              if ($result -eq $true) {
                  $deployedCount++
                  $deploymentResults["Successful"] += $template.properties.displayName
              } elseif ($result -eq $false) {
                  $failedCount++
                  $deploymentResults["Failed"] += $template.properties.displayName
              } else {
                  $skippedCount++
                  $deploymentResults["Skipped"] += $template.properties.displayName
              }
              
              # Rate limiting
              Start-Sleep -Milliseconds 500
          }
          
          # Progress update
          $totalProgress = [Math]::Round((($deployedCount + $failedCount + $skippedCount) / $filteredTemplates.Count) * 100, 1)
          Write-Host "`nProgress: $totalProgress% complete ($($deployedCount + $failedCount + $skippedCount)/$($filteredTemplates.Count) rules processed)"
          
          # Longer pause between batches
          if ($batch -lt $totalBatches - 1) {
              Write-Host "Pausing 5 seconds before next batch..."
              Start-Sleep -Seconds 5
          }
      }
      
      # FINAL SUMMARY
      Write-Host "`n=========================================="
      Write-Host "DEPLOYMENT COMPLETED!"
      Write-Host "=========================================="
      Write-Host "Customer: $customerName" -ForegroundColor Cyan
      Write-Host "Workspace: $workspaceName" -ForegroundColor Cyan
      Write-Host "`nDeployment Statistics:"
      Write-Host "- Total Templates Found: $($allTemplates.Count)"
      Write-Host "- MSSP-Relevant Templates: $($filteredTemplates.Count)"
      Write-Host "- Successfully Deployed: $deployedCount" -ForegroundColor Green
      Write-Host "- Failed Deployments: $failedCount" -ForegroundColor Red
      Write-Host "- Skipped (Invalid): $skippedCount" -ForegroundColor Yellow
      Write-Host "- Success Rate: $([Math]::Round(($deployedCount / $filteredTemplates.Count) * 100, 1))%"
      
      # Show sample of deployed rules
      if ($deploymentResults["Successful"].Count -gt 0) {
          Write-Host "`nSample of deployed rules:" -ForegroundColor Green
          $deploymentResults["Successful"] | Select-Object -First 5 | ForEach-Object {
              Write-Host "  ✓ $_" -ForegroundColor Green
          }
          if ($deploymentResults["Successful"].Count -gt 5) {
              Write-Host "  ... and $($deploymentResults["Successful"].Count - 5) more" -ForegroundColor Green
          }
      }
      
      Write-Host "=========================================="
      
      # Exit code based on results
      if ($deployedCount -eq 0) {
          Handle-Error "No rules were successfully deployed" $true
      } elseif ($deployedCount -lt ($filteredTemplates.Count * 0.5)) {
          Write-Host "WARNING: Less than 50% of rules deployed successfully" -ForegroundColor Yellow
          Write-Host "Check Azure Sentinel portal for details" -ForegroundColor Yellow
      } else {
          Write-Host "`n✓ OOTB Analytics Rules deployment completed successfully!" -ForegroundColor Green
          Write-Host "Navigate to Sentinel Analytics to review deployed rules" -ForegroundColor Green
      }
      
      # Output deployment metrics for logging
      $output = @{
          deployedCount = $deployedCount
          failedCount = $failedCount
          skippedCount = $skippedCount
          totalTemplates = $allTemplates.Count
          msspTemplates = $filteredTemplates.Count
          successRate = [Math]::Round(($deployedCount / $filteredTemplates.Count) * 100, 1)
      }
      
      Write-Output ($output | ConvertTo-Json)
    '''
  }
}

output rulesDeploymentResult object = {
  deploymentName: deployAllOOTBRules.name
  status: 'Completed'
  automationType: 'Full OOTB Deployment'
  targetWorkspace: workspaceName
}
