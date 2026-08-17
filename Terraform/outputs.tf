output "sql_server_fqdn" {
  description = "The hostname to connect to from SSMS / sqlpackage."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_names" {
  description = "Databases created under the logical server."
  value       = sort([for db in azurerm_mssql_database.dbs : db.name])
}

output "admin_login" {
  description = "The admin login created."
  value       = var.sql_admin_login
}

output "resource_group_name" {
  description = "The resource group hosting this lab -- deleted too at the end of the lab."
  value       = azurerm_resource_group.this.name
}
