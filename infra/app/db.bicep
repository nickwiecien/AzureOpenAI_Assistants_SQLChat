param name string
param location string = resourceGroup().location
param tags object = {}

param databaseName string = ''
param keyVaultName string
param connectionStringKey string

@secure()
param sqlAdminPassword string
@secure()
param appUserPassword string

// Because databaseName is optional in main.bicep, we make sure the database name is set here.
var defaultDatabaseName = 'Todo'
var actualDatabaseName = !empty(databaseName) ? databaseName : defaultDatabaseName

module sqlServer '../core/database/sqlserver/sqlserver.bicep' = {
  name: '${name}-deployment'
  params: {
    name: name
    location: location
    tags: tags
    databaseName: actualDatabaseName
    keyVaultName: keyVaultName
    sqlAdminPassword: sqlAdminPassword
    appUserPassword: appUserPassword
    connectionStringKey: connectionStringKey
  }
}

module installSqlServerSchema './db-schema.bicep' = {
  name: '${name}-schema'
  params: {
    name: name
    sqlAdmin: 'sqlAdmin'
    sqlAdminPassword: sqlAdminPassword
    databaseName: sqlServer.outputs.databaseName
    location: location
  }
}

output connectionStringKey string = sqlServer.outputs.connectionStringKey
output databaseName string = sqlServer.outputs.databaseName
