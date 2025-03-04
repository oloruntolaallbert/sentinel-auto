# Sentinel Auto Deployment

This repository provides automated deployment options for Microsoft Sentinel, including Azure Resource Manager (ARM) templates, Bicep files, and an Azure CLI Bash script. Use any of the following methods to deploy a Sentinel instance with a resource group, Log Analytics workspace, common data connectors (Azure Activity, Microsoft Entra ID), and default analytics rules.

## Deploy to Azure (ARM Template)

Deploy the ARM template to Azure with a single click:

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
