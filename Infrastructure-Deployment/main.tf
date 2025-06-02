# Provides configuraiton details for Terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.31.1"
    }
  }
}

# Provides configuration details for the Azure Terraform provider
provider "azurerm" {
  features {}
}

# Provides the Resource Group to logically contain resources
resource "azurerm_resource_group" "vnet_rg" {
  name     = "UK-LDN-vNET"
  location = var.location1
  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}

resource "azurerm_resource_group" "servers_rg" {
  name     = "UK-LDN-Servers"
  location = var.location1
  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}

resource "azurerm_resource_group" "servers_avd_rg" {
  name     = "UK-LDN-Servers-AVD"
  location = var.location1
  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}

#---------- Create vNet
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vNET"
  address_space       = var.addressprefix.default
  location            = azurerm_resource_group.vnet_rg.location
  resource_group_name = azurerm_resource_group.vnet_rg.name
}

#---------- Create Subnet
resource "azurerm_subnet" "web_subnet" {
  name                 = "${var.prefix}-WebSubnet"
  resource_group_name  = azurerm_resource_group.vnet_rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.addressprefix.websubnet1
}

resource "azurerm_subnet" "server_subnet" {
  name                 = "${var.prefix}-ServerSubnet"
  resource_group_name  = azurerm_resource_group.vnet_rg.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.addressprefix.serversubnet1
}

#---------- Create NIC
resource "azurerm_network_interface" "webserver" {
  name                = "${var.prefix}-webserver-nic1"
  location            = azurerm_resource_group.servers_rg.location
  resource_group_name = azurerm_resource_group.servers_rg.name

  ip_configuration {
    name                          = "webserver-ip1"
    subnet_id                     = azurerm_subnet.web_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface" "winserver" {
  name                = "${var.prefix}-winserver-nic1"
  location            = azurerm_resource_group.servers_rg.location
  resource_group_name = azurerm_resource_group.servers_rg.name

  ip_configuration {
    name                          = "winserver-ip1"
    subnet_id                     = azurerm_subnet.server_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

#---------- Create VM
resource "azurerm_virtual_machine" "linuxwebserver" {
  name                  = "${var.prefix}-webserver"
  location              = azurerm_resource_group.servers_rg.location
  resource_group_name   = azurerm_resource_group.servers_rg.name
  network_interface_ids = [azurerm_network_interface.webserver.id]
  #  vm_size               = "Standard_DS1_v2"
  vm_size = "Standard_B2ms"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "${var.prefix}webserver-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  storage_data_disk {
    name              = "${var.prefix}webserver-datadisk1"
    lun               = 0
    caching           = "ReadOnly"
    create_option     = "Empty"
    disk_size_gb      = 128
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "${var.prefix}-LXWEB1"
    admin_username = var.default_linux_creds.username
    admin_password = var.default_linux_creds.password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}

# --- Full steam ahead with Windows Deployment!!!
resource "azurerm_virtual_machine" "winserver" {
  name                  = "${var.prefix}-winserver"
  location              = azurerm_resource_group.servers_rg.location
  resource_group_name   = azurerm_resource_group.servers_rg.name
  network_interface_ids = [azurerm_network_interface.winserver.id]
  vm_size               = "Standard_B2ms"

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}winserver-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  storage_data_disk {
    name              = "${var.prefix}winserver-datadisk1"
    lun               = 0
    caching           = "ReadOnly"
    create_option     = "Empty"
    disk_size_gb      = 128
    managed_disk_type = "Premium_LRS"
  }
  os_profile {
    computer_name  = "${var.prefix}-DC1"
    admin_username = var.default_win_creds.username
    admin_password = var.default_win_creds.password
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }

  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}
