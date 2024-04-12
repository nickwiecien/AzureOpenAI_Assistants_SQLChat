param name string
param location string = resourceGroup().location
param tags object = {}
param chatGptModelVersion string = ''
param chatGptDeploymentName string = ''
param embeddingGptModelName string = ''
param embeddingGptModelVersion string = ''
param embeddingGptDeploymentName string = ''
param chatGptModelName string = ''
param deploymentCapacity int = 30
param keyVaultName string
param aiApiKeySecretName string

module ai '../core/ai/cognitiveservices.bicep' = {
  name: '${name}-deployment'
  params: {
    name: name
    location: location
    tags: tags
    sku: {
      name: 'S0'
    }
    deploymentCapacity: deploymentCapacity
    deployments: [
      {
        name: !empty(chatGptDeploymentName) ? chatGptDeploymentName : 'chat'
        model: {
          format: 'OpenAI'
          name: !empty(chatGptModelName) ? chatGptModelName : 'gpt-4'
          version: !empty(chatGptModelVersion) ? chatGptModelVersion : '1106-Preview'
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: !empty(embeddingGptDeploymentName) ? embeddingGptDeploymentName : 'embedding'
        model: {
          format: 'OpenAI'
          name: !empty(embeddingGptModelName) ? embeddingGptModelName : 'text-embedding-ada-002'
          version: !empty(embeddingGptModelVersion) ? embeddingGptModelVersion : '2'
        }
        sku: {
          name: 'Standard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
}

module aiSecrets './ai-secrets.bicep' = {
  name: '${name}-secrets'
  params: {
    keyVaultName: keyVaultName
    aiAccountName: ai.outputs.openAiName
    aiApiKeySecretName: aiApiKeySecretName
  }
}

output aiEndpoint string = ai.outputs.openAiEndpointUri
output aiName string = ai.outputs.openAiName
output aiApiKeySecretName string = aiApiKeySecretName
