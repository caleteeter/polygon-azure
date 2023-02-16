# Polygon on Azure

[![Deploy To Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcaleteeter%2Fpolygon-azure%2Fmain%2Fmarketplace%2FazureDeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fcaleteeter%2Fpolygon-azure%2Fmain%2Fmarketplace%2FcreateUiDefinition.json) [![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fcaleteeter%2Fpolygon-azure%2Fmain%2Fmarketplace%2FazureDeploy.json)

This template deploys a 4 node Polygon Edge network.

## Prereqs

- Azure CLI - Azure command line interface ([link](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))

- Bicep CLI - Bicep command line interface ([link](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)) 

    `NOTE: By installing AzureCLI you can use bicep by using az bicep`
---

## Deploy

To use the bicep directly (non-production), the following should be executed:

```
az group create --name <desired name for resource group> --location <desired region>

az deployment group create --resource-group <resource group from above> --template-file <path to bicep template> 
```

---

## Build

The source for the solution is created in Bicep, however to use directly in Azure Marketplace, requires ARM (Azure Resource Manager) templates.  Bicep can output the required ARM template by executing the following:

```
bicep build --file main.bicep
```