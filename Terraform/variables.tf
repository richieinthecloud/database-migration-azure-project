variable "resource_group_name" {
  description = "The name of the resource group in which to create the resources."
  type        = string
  default     = "rg-sql-migration-lab"
}

variable "location" {
  description = "The Azure region in which to create the resources."
  type        = string
  default     = "eastus"
}

variable "sql_server_name" {
  description = "The name of the Azure SQL Server to create. Must be globally unique. Becomes <name>.database.windows.net. Lowercase letters, numbers, and hyphens only."
  type        = string
}

variable "sql_admin_login" {
  description = "The administrator login name for the SQL Server."
  type        = string
  default     = "sqladmin"
}

variable "sql_admin_password" {
  description = "The password for the SQL Server administrator."
  type        = string
  sensitive   = true
}

variable "database_names" {
  description = "The name of the Azure SQL Database to create."
  type        = list(string)
  default     = ["Data_Warehouse", "MyDatabase", "nbadb", "SalesDB"]
}

variable "sku_name" {
  description = "Service tier for EACH database. 'Basic' is the cheapest fixed tier. 'GP_S_Gen5_1' is serverless General Purpose that auto-pauses to save money."
  type        = string
  default     = "Basic"
}

variable "client_ip_address" {
  description = "Your current public IP address, added as a firewall rule so SSMS can connect. Find it at https://whatismyip.com."
  type        = string
}

variable "allow_azure_services" {
  description = "When true, adds the 'Allow Azure Services' firewall rule so the portal query editor can connect."
  type        = bool
  default     = true
}

