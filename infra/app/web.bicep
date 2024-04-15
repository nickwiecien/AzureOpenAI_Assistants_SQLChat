param name string
param location string = resourceGroup().location
param tags object = {}
param serviceName string = 'web'
param appCommandLine string = 'python -m streamlit run app_assistants.py --server.port 8000 --server.address 0.0.0.0'
param applicationInsightsName string = ''
param appServicePlanId string
param keyVaultName string
param applicationInsightsInstrumentationKey string
param aiApiKeySecretName string
param aiEndpoint string
param sqlConnectionStringKey string
param chatModelDeploymentName string

module web '../core/host/appservice.bicep' = {
  name: '${name}-deployment'
  params: {
    name: name
    location: location
    appCommandLine: appCommandLine
    applicationInsightsName: applicationInsightsName
    appServicePlanId: appServicePlanId
    runtimeName: 'python'
    runtimeVersion: '3.12'
    tags: union(tags, { 'azd-service-name': serviceName })
    scmDoBuildDuringDeployment: true
    keyVaultName: keyVaultName
  }
}

module appSettings '../core/host/appservice-appsettings.bicep' = {
  name: '${name}-appSettings-deployment'
  params: {
    appSettings: {
      APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsightsInstrumentationKey
      KEYVAULT_NAME: keyVaultName
      SQL_DB_CONNECTION_STRING: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${sqlConnectionStringKey})'
      AZURE_OPENAI_API_KEY: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${aiApiKeySecretName})'
      AZURE_OPENAI_API_ENDPOINT: aiEndpoint
      AZURE_OPENAI_API_VERSION: '2024-02-15-preview'
      AZURE_OPENAI_CHAT_MODEL_DEPLOYMENT_NAME: chatModelDeploymentName
      SCM_DO_BUILD_DURING_DEPLOYMENT: true
    }    
    name: web.outputs.name
  }
}

output SERVICE_WEB_IDENTITY_PRINCIPAL_ID string = web.outputs.identityPrincipalId
output SERVICE_WEB_NAME string = web.outputs.name
output SERVICE_WEB_URI string = web.outputs.uri
