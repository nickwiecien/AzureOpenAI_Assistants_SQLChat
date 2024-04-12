targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// Optional parameters to override the default azd resource naming conventions. Update the main.parameters.json file to provide values. e.g.,:
// "resourceGroupName": {
//      "value": "myGroupName"
// }
param applicationInsightsDashboardName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param keyVaultName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param webServiceName string = ''
@secure()
param appUserPassword string = ''
@secure()
param sqlAdminPassword string = ''
param sqlServerName string = ''
param sqlDatabaseName string = ''
param azureOpenAiName string = ''
param chatGptModelVersion string = ''
param chatGptDeploymentName string = ''
param embeddingGptModelName string = ''
param embeddingGptModelVersion string = ''
param embeddingGptDeploymentName string = ''
param chatGptModelName string = ''
param deploymentCapacity int = 30
param principalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module sql './core/database/sqlserver/sqlserver.bicep' = {
  scope: rg
  name: 'sql'
  params: {
    appUserPassword: appUserPassword
    databaseName: !empty(sqlDatabaseName) ? sqlDatabaseName : '${abbrs.sqlServersDatabases}${resourceToken}'
    keyVaultName: keyVault.outputs.name
    name: !empty(sqlServerName) ? sqlServerName : '${abbrs.sqlServers}${resourceToken}'
    sqlAdminPassword: sqlAdminPassword
    location: location
    connectionStringKey: 'SqlConnectionString'
    tags: tags
  }
}

// The application frontend
module web './app/web.bicep' = {
  name: 'web'
  scope: rg
  params: {
    name: !empty(webServiceName) ? webServiceName : '${abbrs.webSitesAppService}web-${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    keyVaultName: keyVault.outputs.name
  }
}

// Give the API access to KeyVault
module apiKeyVaultAccess './core/security/keyvault-access.bicep' = {
  name: 'api-keyvault-access'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: web.outputs.SERVICE_WEB_IDENTITY_PRINCIPAL_ID
  }
}

// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'B1'
    }
  }
}

// Store secrets in a keyvault
module keyVault './core/security/keyvault.bicep' = {
  name: 'keyvault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    principalId: principalId
  }
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

module appSettings './core/host/appservice-appsettings.bicep' = {
  scope: rg
  name: 'appSettings'
  params: {
    appSettings: {
      APPINSIGHTS_INSTRUMENTATIONKEY: monitoring.outputs.applicationInsightsInstrumentationKey
      KEYVAULT_NAME: keyVault.outputs.name
      SQL_DB_CONNECTION_STRING: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.name};SecretName=${sql.outputs.connectionStringKey})'
      AZURE_OPENAI_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.name};SecretName=${ai.outputs.aiApiKeySecretName})'
      AZURE_OPENAI_API_ENDPOINT: ai.outputs.aiEndpoint
      AZURE_OPENAI_API_VERSION: '2024-02-15-preview'
      SCM_DO_BUILD_DURING_DEPLOYMENT: 1
    }
    name: web.outputs.SERVICE_WEB_NAME
  }
}

module ai './app/ai.bicep' = {
  scope: rg
  name: 'ai'
  params: {
    name: !empty(azureOpenAiName) ? azureOpenAiName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    aiApiKeySecretName: 'openai-api-key'
    chatGptDeploymentName: chatGptDeploymentName
    chatGptModelName: chatGptModelName
    chatGptModelVersion: chatGptModelVersion
    embeddingGptDeploymentName: embeddingGptDeploymentName
    embeddingGptModelName: embeddingGptModelName
    embeddingGptModelVersion: embeddingGptModelVersion
    deploymentCapacity: deploymentCapacity
    keyVaultName: keyVault.outputs.name
    location: location
    tags: tags
  }
}

// Data outputs
output AZURE_SQL_CONNECTION_STRING_KEY string = sql.outputs.connectionStringKey
output AZURE_SQL_DATABASE_NAME string = sql.outputs.databaseName

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output WEB_APP_BASE_URL string = web.outputs.SERVICE_WEB_URI
