terraform {
    required_providers {
        azurerm = {
            source = "hashicorp/azurerm"
            version = "~>2.0"
        }
    }
}

provider "azurerm" {
    features {}

    subscription_id   = var.subscription_id
    tenant_id         = var.tenant_id
    client_id         = var.client_id
    client_secret     = var.client_secret
}

resource "random_id" "suffix" {
    byte_length = 4
}

resource "azurerm_resource_group" "rg" {
    name        = "${var.prefix}-rg-${random_id.suffix.hex}"
    location    = var.region
}

resource "azurerm_virtual_network" "network" {
    name                = "${var.prefix}-net-${random_id.suffix.hex}"
    address_space       = ["10.0.0.0/23"]
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
}

resource "azurerm_subnet" "subnet" {
    name                 = "${var.prefix}-subnet-${random_id.suffix.hex}"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.network.name
    address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "sg" {
    name                = "${var.prefix}-sg-${random_id.suffix.hex}"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location

    security_rule {
        name                       = "HTTP"
        priority                   = 101
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "nic" {
    name                = "${var.prefix}-nic-${random_id.suffix.hex}"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location

    ip_configuration {
        name                          = "${var.prefix}-niccfg-${random_id.suffix.hex}"
        subnet_id                     = azurerm_subnet.subnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "nic_assoc" {
    network_interface_id      = azurerm_network_interface.nic.id
    network_security_group_id = azurerm_network_security_group.sg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
    name                = "${var.prefix}-vm-${random_id.suffix.hex}"
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    size                = "Standard_F2"
    admin_username      = "azureuser"

    network_interface_ids = [
        azurerm_network_interface.nic.id,
    ]

    admin_ssh_key {
        username   = "azureuser"
        public_key = var.admin_key_public
    }

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = var.image.publisher
        offer     = var.image.offer
        sku       = var.image.sku
        version   = var.image.version
    }
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.vm.name
}


resource "azurerm_mysql_flexible_server" "mysql-server" {
  name = "${var.prefix}-mysql-server"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
 
  administrator_login = var.admin_login
  administrator_password = var.admin_password
 
  sku_name = "GP_Standard_D2ds_v4"
  version = "5.7"
}

resource "azurerm_mysql_flexible_database" "mysql-db" {
  name                = "${var.prefix}_mysql"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql-server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
}

resource "azurerm_mysql_flexible_server_firewall_rule" "mysql-fw-rule" {
  name                = "${var.prefix}-mysql-fw-rule"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql-server.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

output "mysql_server" {
  value = azurerm_mysql_flexible_server.mysql-server
  sensitive = true
}

output mysql_db {
  value = azurerm_mysql_flexible_database.mysql-db.name
}

variable "region" {
  type = string
  description = "Region to launch servers."
}

variable "admin_user" {
  type = string
  description = "Admin user for the image we're launching"
}

variable "admin_key_public" {
  type = string
  description = "Public SSH key of admin user"
}

variable "image" {
  type = object({
    publisher = string
    offer = string
    sku = string
    version = string
  })
  default = {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "18.04-LTS"
    version = "latest"
  }
}

variable "subscription_id" {
  type = string
  description = "Azure subscription ID"
}

variable "tenant_id" {
  type = string
  description = "Azure Tenant ID"
}

variable "client_id" {
  type = string
  description = "Azure client (application) ID"
}

variable "client_secret" {
  type = string
  description = "Azure client (application) secret"
}

variable "prefix" {
  type = string
  description = "Resource name prefix"
  default = "cfy"
}

variable "admin_login" {
  default = "cloudify"
}

variable "admin_password"{
  default = "Q!hvDtRbSFD_"
}