param location string
param name string
param sqlAdmin string
@secure()
param sqlAdminPassword string
param databaseName string

resource sqlServer 'Microsoft.Sql/servers@2014-04-01' existing = {
  name: name
}

resource sqlDeploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${name}-schema-deployment-script'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.52.0'
    retentionInterval: 'PT1H' // Retain the script resource for 1 hour after it ends running
    timeout: 'PT5M' // Five minutes
    cleanupPreference: 'OnExpiration'
    environmentVariables: [
      {
        name: 'DBNAME'
        value: databaseName
      }
      {
        name: 'DBSERVER'
        value: sqlServer.properties.fullyQualifiedDomainName
      }
      {
        name: 'SQLCMDPASSWORD'
        secureValue: sqlAdminPassword
      }
      {
        name: 'SQLADMIN'
        value: sqlAdmin
      }
    ]


    scriptContent: '''
apk add dotnet6-sdk

dotnet tool install -g microsoft.sqlpackage

export PATH="$PATH:/root/.dotnet/tools"

wget https://github.com/nickwiecien/AzureOpenAI_Assistants_SQLChat/blob/b64ea81bf7c36aae703d21e08a44deed38b748a1/infra/data/adventureworkslt.bacpac

sqlpackage /Action:Import /SourceFile:"adventureworkslt.bacpac" /tsn:"tcp:$DBSERVER,1433" /tdn:"$DBNAME" /tu:"$SQLADMIN" /tp:"$SQLCMDPASSWORD"
    '''
  }
}
