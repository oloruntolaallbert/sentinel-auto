# Sentinel Auto Deployment

This repository provides automated deployment options for Microsoft Sentinel, including Azure Resource Manager (ARM) templates, Bicep files, and an Azure CLI Bash script. Use any of the following methods to deploy a Sentinel instance with a resource group, Log Analytics workspace, common data connectors (Azure Activity, Microsoft Entra ID), and default analytics rules.

## Deploy to Azure (ARM Template)

Deploy the ARM template to Azure with a single click:
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2FARM%2Ftemplate.json)

**Notes for ARM Deployment**:
- Requires an Azure subscription with appropriate permissions.
- You’ll be prompted to specify or accept default values for `location`, `resourceGroupName`, `workspaceName`, and `sentinelInstanceName`.
- Use the `arm/parameters.json` file for predefined parameter values if desired.
- Data connectors supported for now
- --Entra ID Protection
- --Defender XDR

## Deploy to Azure (Bicep Template)

Deploy the Bicep template to Azure with a single click:
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2FBicep%2Fcompiled%2Fdeploy.json)
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2FBicep%2Fmain.bicep)

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
## 🚀 One-Click MSSP Sentinel Deployment

Deploy complete Microsoft Sentinel with all OOTB analytics rules:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2Fnew%2Fmain.bicep)


**What gets deployed:**
- ✅ Microsoft Sentinel workspace
- ✅ 9 data connectors 
- ✅ 200+ OOTB analytics rules (auto-deployed)
- ✅ Data Collection Rules for AMA
- ✅ Complete MSSP configuration
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Foloruntolaallbert%2Fsentinel-auto%2Fmain%2Fnew%2Fmain.json)
**Just enter:** Customer Name + Region = Done!
