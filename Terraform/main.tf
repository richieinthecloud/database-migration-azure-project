resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
}

# The cloud SQL server: a network endpoint (sqlmig-lab-rac-001.database.windows.net)
# plus an admin identity and firewall. It is not a SQL Server instance and holds no data itself.
# the databses below all live under this one server 

resource "azurerm_mssql_server" "this" {
  name                         = var.sql_server_name
  resource_group_name          = azurerm_resource_group.this.name
  location                     = azurerm_resource_group.this.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
}

# one database per entry in var.database_names -- the 4 that are in my SSMS, all fall under the 
# single logical server above. Each is sized independently by var.sku_name. 
resource "azurerm_mssql_database" "dbs" {
  for_each  = toset(var.database_names)
  name      = each.value
  server_id = azurerm_mssql_server.this.id
  sku_name  = var.sku_name

  # lets 'terraform destroy' tear the lab down cleanly when done. 
  lifecycle {
    prevent_destroy = false
  }
}

# firewall rule: allow your workstation (where SMSS runs) to reach the server. 
resource "azurerm_mssql_firewall_rule" "client" {
  name             = "allow-client-ip"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}

# optional: the 0.0.0.0 start/end pair is Azure's documented 'allow azure services' rule. 
# it does not open the server to the public internet 
# it lets the portal's built-in query editor and other Azure services connect. 

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  count            = var.allow_azure_services ? 1 : 0
  name             = "allow-azure-services"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
