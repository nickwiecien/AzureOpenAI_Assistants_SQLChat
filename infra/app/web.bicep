param name string
param location string = resourceGroup().location
param tags object = {}
param serviceName string = 'web'
param appCommandLine string = 'python -m streamlit run main.py --server.port 8000 --server.address 0.0.0.0'
param applicationInsightsName string = ''
param appServicePlanId string
param keyVaultName string

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

output SERVICE_WEB_IDENTITY_PRINCIPAL_ID string = web.outputs.identityPrincipalId
output SERVICE_WEB_NAME string = web.outputs.name
output SERVICE_WEB_URI string = web.outputs.uri
