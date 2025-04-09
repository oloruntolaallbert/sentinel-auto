#!/bin/bash
# Microsoft Sentinel Deployment Script
# This script automates the deployment of Microsoft Sentinel using Azure CLI

# Set text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                                                          ║"
echo "║               MICROSOFT SENTINEL DEPLOYER                ║"
echo "║                                                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed.${NC}"
    echo "Please install Azure CLI first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check login status
echo -e "${YELLOW}Checking Azure login status...${NC}"
az account show &> /dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}You are not logged in to Azure CLI. Please login:${NC}"
    az login
    if [ $? -ne 0 ]; then
        echo -e "${RED}Login failed. Exiting script.${NC}"
        exit 1
    fi
fi

# Get current subscription ID
CURRENT_SUB=$(az account show --query id -o tsv)
echo -e "${GREEN}Currently logged into subscription:${NC} $CURRENT_SUB"

# Ask for subscription ID or use current
read -p "Enter subscription ID (press Enter to use current): " SUBSCRIPTION_ID
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$CURRENT_SUB}

# Set subscription
echo -e "${YELLOW}Setting subscription to ${SUBSCRIPTION_ID}...${NC}"
az account set --subscription $SUBSCRIPTION_ID
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to set subscription. Exiting script.${NC}"
    exit 1
fi

# Ask for resource group name
read -p "Enter resource group name: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
    echo -e "${RED}Resource group name cannot be empty. Exiting script.${NC}"
    exit 1
fi

# Ask for location
echo -e "${YELLOW}Available locations:${NC}"
az account list-locations --query "[].{Name:name}" -o tsv | sort | head -n 10
echo "..."
read -p "Enter location (e.g., eastus): " LOCATION
if [ -z "$LOCATION" ]; then
    LOCATION="eastus"
    echo -e "${YELLOW}Using default location: ${LOCATION}${NC}"
fi

# Ask for Log Analytics workspace name
read -p "Enter Log Analytics workspace name: " WORKSPACE_NAME
if [ -z "$WORKSPACE_NAME" ]; then
    WORKSPACE_NAME="${RESOURCE_GROUP}-workspace"
    echo -e "${YELLOW}Using default workspace name: ${WORKSPACE_NAME}${NC}"
fi

# Ask for tags (optional)
read -p "Enter environment tag (default: Development): " ENV_TAG
ENV_TAG=${ENV_TAG:-"Development"}

TAGS="environment=${ENV_TAG} project=SecurityEngineering owner=SecurityTeam costCenter=IT"

# Create resource group
echo -e "${YELLOW}Creating resource group ${RESOURCE_GROUP}...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION --tags $TAGS
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create resource group. Exiting script.${NC}"
    exit 1
fi

# Create Log Analytics workspace
echo -e "${YELLOW}Creating Log Analytics workspace ${WORKSPACE_NAME}...${NC}"
az monitor log-analytics workspace create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $WORKSPACE_NAME \
    --location $LOCATION \
    --sku PerGB2018 \
    --retention-time 30 \
    --tags $TAGS

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create Log Analytics workspace. Exiting script.${NC}"
    exit 1
fi

# Get workspace resource ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $WORKSPACE_NAME \
    --query id -o tsv)

# Enable Microsoft Sentinel
echo -e "${YELLOW}Enabling Microsoft Sentinel...${NC}"
az security insights create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $WORKSPACE_NAME \
    -n $WORKSPACE_NAME

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to enable Microsoft Sentinel. Exiting script.${NC}"
    exit 1
fi

# Enable Azure Activity data connector
echo -e "${YELLOW}Enabling Azure Activity data connector...${NC}"
DIAGNOSTIC_SETTING_NAME="SentinelActivity"

# First, create a diagnostic setting to send activity logs to Log Analytics
az monitor diagnostic-settings create \
    --name $DIAGNOSTIC_SETTING_NAME \
    --resource "/subscriptions/$SUBSCRIPTION_ID" \
    --workspace $WORKSPACE_ID \
    --logs '[{"category": "Administrative", "enabled": true}, {"category": "Security", "enabled": true}, {"category": "Alert", "enabled": true}]'

# Attempt to enable Azure AD connector (note: this might require additional permissions)
echo -e "${YELLOW}Attempting to enable Azure AD data connector...${NC}"
echo -e "${BLUE}Note: This may require additional permissions and Graph API access.${NC}"
echo -e "${BLUE}If this step fails, you can enable connectors manually in the Azure Portal.${NC}"

# Output success message
echo -e "${GREEN}Microsoft Sentinel has been successfully deployed!${NC}"
echo -e "${GREEN}Resource Group:${NC} $RESOURCE_GROUP"
echo -e "${GREEN}Log Analytics Workspace:${NC} $WORKSPACE_NAME"
echo -e "${GREEN}Workspace Resource ID:${NC} $WORKSPACE_ID"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Visit the Azure Portal to configure additional data connectors"
echo "2. Set up analytics rules and playbooks"
echo "3. Configure workbooks and hunting queries"
echo ""
echo -e "${YELLOW}Portal URL:${NC} https://portal.azure.com/#blade/Microsoft_Azure_Security_Insights/MainMenuBlade/Overview/WorkspaceId/${WORKSPACE_ID}"
