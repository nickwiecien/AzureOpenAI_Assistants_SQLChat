param aiAccountName string
param aiApiKeySecretName string
param keyVaultName string

resource aiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: aiAccountName
}

resource aiApiKeySercret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: aiApiKeySecretName
  properties: {
    value: aiAccount.listKeys().key1
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}
