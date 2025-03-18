# Sentinel Auto Deployment

This repository provides automated deployment options for Microsoft Sentinel, including Azure Resource Manager (ARM) templates, Bicep files, and an Azure CLI Bash script. Use any of the following methods to deploy a Sentinel instance with a resource group, Log Analytics workspace, common data connectors (Azure Activity, Microsoft Entra ID), and default analytics rules.

## Deploy to Azure (ARM Template)

Deploy the ARM template to Azure with a single click:
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2Farm%2Ftemplate.json)
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2F/oloruntolaallbert%2Fsentinel-auto%2F-/raw%2Fmain%2Farm%2Ftemplate.json)

**Notes for ARM Deployment**:
- Requires an Azure subscription with appropriate permissions.
- You’ll be prompted to specify or accept default values for `location`, `resourceGroupName`, `workspaceName`, and `sentinelInstanceName`.
- Use the `arm/parameters.json` file for predefined parameter values if desired.

## Deploy to Azure (Bicep Template)

Deploy the Bicep template to Azure with a single click:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2F/oloruntolaallbert%2Fsentinel-auto%2F-/raw%2Fmain%2Fbicep%2Fmain.bicep)

**Notes for Bicep Deployment**:
- Bicep is compiled to ARM JSON by Azure during deployment.
- Ensure Azure supports direct Bicep deployment (as of March 2025, this is supported; otherwise, compile `main.bicep` to `template.json` locally).
- You’ll be prompted to specify or accept default values for `location`, `resourceGroupName`, `workspaceName`, and `sentinelInstanceName`.
- Use the `bicep/parameters.json` file for predefined parameter values if desired.

## Deploy Using Azure CLI (Bash Script)

Use the interactive Bash script to deploy Microsoft Sentinel via Azure CLI.

### Prerequisites
- Azure CLI installed and authenticated (`az login`).
- Bash environment (e.g., Cloud Shell, WSL, or Linux terminal).

### Steps
1. Navigate to the `scripts/` directory in this repository.
2. Run the script:
   ```bash
   chmod +x setup_sentinel.sh
   ./setup_sentinel.sh
3 Follow the prompts to input:
Subscription ID (defaults to current subscription).
Resource Group Name.
Azure Region (e.g., eastus).
Log Analytics Workspace Name.
Sentinel Instance Name.
Notes
The script creates a resource group, Log Analytics workspace, enables Sentinel, and installs Azure Activity and Microsoft Entra ID data connectors with default analytics rules.
Check the Azure Portal after deployment to verify and configure additional settings.

## Deploy Using Terraform
Use Terraform to declaratively deploy Microsoft Sentinel infrastructure.

Prerequisites
Terraform installed (download from terraform.io).
Azure CLI installed and authenticated (az login).
Azure provider configured for Terraform.
Steps
Navigate to the terraform/ directory in this repository.
Initialize the Terraform working directory:
bash
terraform init
Create a terraform.tfvars file or set variables interactively:
hcl
location              = "eastus"
resource_group_name   = "SentinelRG"
workspace_name        = "SentinelWorkspace"
sentinel_instance_name = "SentinelInstance"
Plan the deployment to preview changes:
bash
terraform plan
Apply the configuration to deploy resources:
bash
terraform apply
Notes
Terraform supports basic Sentinel resources (e.g., resource group, Log Analytics workspace, Sentinel onboarding, and some data connectors) via the azurerm provider.
Advanced features (e.g., analytics rules, complex connectors) may require the azapi provider or PowerShell scripts (see scripts/import_sentinel_rules.ps1 for an example).
Use the terraform/outputs.tf file to verify deployed resources.
Additional Information
ARM Template: Located in arm/template.json. More verbose but fully mature for complex deployments.
Bicep Template: Located in bicep/main.bicep. Simpler syntax, better Azure integration, ideal for Azure-only deployments.
Bash Script: Located in scripts/setup_sentinel.sh. Interactive and CLI-based for manual deployment.
Terraform Configuration: Located in terraform/. Uses IaC for declarative deployment with potential workarounds for advanced Sentinel features.
CI/CD: A .gitlab-ci.yml file is included for validating templates. Adjust the pipeline as needed for your workflow.
Prerequisites for All Methods
An Azure subscription with permissions to create resources (e.g., Contributor role).
For Bicep, ensure the Bicep CLI or Azure support for Bicep is available.
For ARM, no additional tools are required beyond Azure CLI or Portal.
For Terraform, install Terraform and configure the Azure provider.
Contributing
Feel free to fork this repository, make improvements (e.g., adding more data connectors, rules, or Terraform enhancements), and submit pull requests
