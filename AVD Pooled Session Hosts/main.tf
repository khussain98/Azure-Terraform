# ------------------------------------------------------------
# 1) Provider Configuration
# ------------------------------------------------------------
# (Assumed to be defined in providers.tf)

# ------------------------------------------------------------
# 2) Locals
# ------------------------------------------------------------
locals {
  # Grab the AVD host pool registration token
  registration_token = azurerm_virtual_desktop_host_pool_registration_info.registrationinfo.token
}

# ------------------------------------------------------------
# 3) Resource Groups
# ------------------------------------------------------------
resource "azurerm_resource_group" "rg_vnet" {
  name     = var.rg_vnet
  location = var.resource_group_location
}

resource "azurerm_resource_group" "rg_servers" {
  name     = var.rg_servers
  location = var.resource_group_location
}

resource "azurerm_resource_group" "rg" {
  name     = var.rg
  location = var.resource_group_location
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group 

# ------------------------------------------------------------
# 4) Virtual Network & Subnet
# ------------------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["192.168.0.0/16"]
  location            = azurerm_resource_group.rg_vnet.location
  resource_group_name = azurerm_resource_group.rg_vnet.name
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network 

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg_vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.10.0/24"]
}

# ------------------------------------------------------------
# 5) Network Security Group for AVD Hosts
# ------------------------------------------------------------
resource "azurerm_network_security_group" "avd_nsg" {
  name                = "${var.prefix}-avd-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow inbound AD/DC traffic from within the VNet
  security_rule {
    name                       = "Allow-AD-DC"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["389", "636", "445"]
    source_address_prefix      = azurerm_subnet.subnet.address_prefixes[0]
    destination_address_prefix = "192.168.10.10"   # DC’s static IP
  }

  # Allow AVD gateway flow (RDP) via AzureLoadBalancer
  security_rule {
    name                       = "Allow-AVD-Gateway"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Outbound HTTPS (for DSC modules, Windows Update, etc.)
  security_rule {
    name                       = "Allow-Outbound-HTTPS"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group 

resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.avd_nsg.id
}

# ------------------------------------------------------------
# 6) Blank NSG for the DC (DNS) NIC
# ------------------------------------------------------------
resource "azurerm_network_security_group" "dc_nsg" {
  name                = "${var.prefix}-dc-nsg"
  location            = azurerm_resource_group.rg_servers.location
  resource_group_name = azurerm_resource_group.rg_servers.name

  # No custom security_rule blocks → only Azure’s default NSG rules apply 
  # (AllowVnetInBound, AllowAzureLoadBalancerInBound, DenyAllInbound, etc.).
}
# Docs on default NSG rules: https://learn.microsoft.com/azure/firewall/nsg-overview#default-inbound-rules 

# ------------------------------------------------------------
# 7) Deploy Base Windows Server for DC Creation
# ------------------------------------------------------------
resource "azurerm_network_interface" "DC01" {
  name                = "${var.prefix}-DC01-nic1"
  location            = azurerm_resource_group.rg_servers.location
  resource_group_name = azurerm_resource_group.rg_servers.name

  # Point the DC’s DNS to itself so it can host your AD DNS zone.
  dns_servers = [
    "127.0.0.1"
  ]

  ip_configuration {
    name                          = "DC01-ip1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "192.168.10.10"
  }

  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}

# Associate the blank NSG to the DC NIC, enforcing only default NSG rules 
resource "azurerm_network_interface_security_group_association" "dc_nic_nsg" {
  network_interface_id      = azurerm_network_interface.DC01.id
  network_security_group_id = azurerm_network_security_group.dc_nsg.id
}

resource "azurerm_virtual_machine" "DC01" {
  name                  = "${var.prefix}-DC01"
  location              = azurerm_resource_group.rg_servers.location
  resource_group_name   = azurerm_resource_group.rg_servers.name
  network_interface_ids = [azurerm_network_interface.DC01.id]
  vm_size               = var.vm_size

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "${var.prefix}-DC01-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${var.prefix}-DC01"
    admin_username = var.local_admin_username
    admin_password = var.local_admin_password
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
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine 

# 7.4) Custom Script Extension: Install AD DS + Create new forest "ad.khlab.com"
#
# This runs a one-liner PowerShell that:
#   1) Installs the AD-Domain-Services feature
#   2) Promotes DC01 into a brand-new forest called ad.khlab.com
#      (with NetBIOS name "ADKHLAB" and DNS enabled)
#
# Variables needed:
#   - var.dsrp_password: the SafeMode (DSRM) password for the new forest
#
# References:
#   - Custom Script Extension docs: https://learn.microsoft.com/azure/virtual-machines/extensions/custom-script-windows 
#   - Install-ADDSForest cmdlet:    https://learn.microsoft.com/powershell/module/activedirectory/install-addsforest 
resource "azurerm_virtual_machine_extension" "dc_customscript" {
  name                       = "${var.prefix}-DC01-CustomScript"
  virtual_machine_id         = azurerm_virtual_machine.DC01.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "commandToExecute": "powershell -ExecutionPolicy Unrestricted -NoProfile -Command Install-WindowsFeature AD-Domain-Services; Install-ADDSForest -DomainName 'ad.khlab.com' -SafeModeAdministratorPassword (ConvertTo-SecureString '${var.dsrp_password}' -AsPlainText -Force) -DomainNetbiosName 'ADKHLAB' -InstallDns -Force:$true -NoRebootOnCompletion"
    }
  SETTINGS

  protected_settings = <<-PROTECTED
    {
      "storageAccountName": null,
      "storageAccountKey": null
    }
  PROTECTED
}

# ------------------------------------------------------------
# 8) AVD Host Pool
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool" "hostpool" {
  name                 = "${var.prefix}-hostpool"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  type                 = "Pooled"       # or "Personal"
  load_balancer_type   = "BreadthFirst" # “BreadthFirst”, “DepthFirst”, or “Persistent”
  friendly_name        = "${var.prefix} Host Pool"
  validate_environment = true
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool 

# ------------------------------------------------------------
# 9) AVD Application Group
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_application_group" "dag" {
  name                = "${var.prefix}-dag"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  host_pool_id        = azurerm_virtual_desktop_host_pool.hostpool.id
  type                = "Desktop" # or "RemoteApp"
  friendly_name       = "${var.prefix} Application Group"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_application_group 

# ------------------------------------------------------------
# 10) AVD Workspace & Association
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_workspace" "workspace" {
  name                = "${var.prefix}-workspace"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  friendly_name       = "${var.prefix} Workspace"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_workspace 

resource "azurerm_virtual_desktop_workspace_application_group_association" "association" {
  workspace_id         = azurerm_virtual_desktop_workspace.workspace.id
  application_group_id = azurerm_virtual_desktop_application_group.dag.id
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_workspace_application_group_association 

# ------------------------------------------------------------
# 11) Host Pool Registration Info (token for DSC)
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool_registration_info" "registrationinfo" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.hostpool.id
  expiration_date = var.registration_expiration   # e.g. "2025-12-01T00:00:00Z"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool_registration_info 

# ------------------------------------------------------------
# 12) Random String for AVD session host local passwords
# ------------------------------------------------------------
resource "random_string" "AVD_local_password" {
  count            = var.rdsh_count
  length           = 16
  special          = true
  min_special      = 2
  override_special = "*!@#?"
}
# Docs: https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string 

# ------------------------------------------------------------
# 13) Storage Account + File Shares for FSLogix / MSIX
# ------------------------------------------------------------
resource "azurerm_storage_account" "avd_storage" {
  name                      = "${lower(replace(var.prefix, "-", ""))}storage" # 3–24 chars, lowercase alphanumeric 
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Premium"
  account_replication_type  = "LRS"
  account_kind              = "FileStorage"
  enable_https_traffic_only = true
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account 

resource "azurerm_storage_share" "fslogix" {
  name                 = "fslogix"
  storage_account_name = azurerm_storage_account.avd_storage.name
  quota                = 1024
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share 

resource "azurerm_storage_share" "msix" {
  name                 = "msix"
  storage_account_name = azurerm_storage_account.avd_storage.name
  quota                = 1024
}

# ------------------------------------------------------------
# 14) Azure AD Groups for AVD Admins & Users
# ------------------------------------------------------------
resource "azuread_group" "avd_admins" {
  display_name     = "AVD Admins"
  security_enabled = true
}
# Docs: https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group 

resource "azuread_group" "avd_users" {
  display_name     = "AVD Users"
  security_enabled = true
}

# ------------------------------------------------------------
# 14b) Grant AVDUsers the “Storage File Data SMB Share Contributor” role
#       on the storage account (so they can mount fslogix/msix shares).
# ------------------------------------------------------------

# 1) Look up the built-in “Storage File Data SMB Share Contributor” role at the storage-account scope
data "azurerm_role_definition" "storage_file_smb_contributor" {
  name  = "Storage File Data SMB Share Contributor"
  scope = azurerm_storage_account.avd_storage.id
}

# 2) Assign that role to your AVDUsers group on the storage-account
resource "azurerm_role_assignment" "fslogix_users_on_storage" {
  scope              = azurerm_storage_account.avd_storage.id
  role_definition_id = data.azurerm_role_definition.storage_file_smb_contributor.id
  principal_id       = azuread_group.avd_users.id
}

# ------------------------------------------------------------
# 15) Role Definitions & Assignments
# ------------------------------------------------------------
/**
# 15.1) Capture the current subscription ID via az login context
data "azurerm_subscription" "current" {}

# 15.2) Find the built-in "Desktop Virtualization User" role
data "azurerm_role_definition" "desktop_virtualization_user" {
  name  = "Desktop Virtualization User"
  scope = data.azurerm_subscription.current.id
}

# 15.3) Find the built-in "Desktop Virtualization Administrator" role
data "azurerm_role_definition" "desktop_virtualization_admin" {
  name  = "Desktop Virtualization Administrator"
  scope = data.azurerm_subscription.current.id
}

# 15.4) Assign Desktop Virtualization User to the AVDUsers group at the App Group
resource "azurerm_role_assignment" "avd_users_assignment" {
  scope              = azurerm_virtual_desktop_application_group.dag.id
  role_definition_id = data.azurerm_role_definition.desktop_virtualization_user.id
  principal_id       = azuread_group.avd_users.id
}

# 15.5) Assign Desktop Virtualization Administrator to the AVDAdmins group at the Host Pool
resource "azurerm_role_assignment" "avd_admins_assignment" {
  scope              = azurerm_virtual_desktop_host_pool.hostpool.id
  role_definition_id = data.azurerm_role_definition.desktop_virtualization_admin.id
  principal_id       = azuread_group.avd_admins.id
}
**/
# ------------------------------------------------------------
# 16) Network Interfaces for Session Hosts
# ------------------------------------------------------------
resource "azurerm_network_interface" "avd_vm_nic" {
  count               = var.rdsh_count
  name                = "${var.prefix}-${count.index + 1}-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Session hosts point DNS to the DC (192.168.10.10) 
  dns_servers = [
    "192.168.10.10"
  ]

  ip_configuration {
    name                          = "nic${count.index + 1}_config"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "192.168.10.${20 + count.index}"
  }
}

# ------------------------------------------------------------
# 17) Windows Virtual Machines (Session Hosts)
# ------------------------------------------------------------
resource "azurerm_windows_virtual_machine" "avd_vm" {
  count               = var.rdsh_count
  name                = "${var.prefix}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  network_interface_ids = [
    azurerm_network_interface.avd_vm_nic[count.index].id
  ]
  provision_vm_agent = true
  admin_username     = var.local_admin_username
  admin_password     = var.local_admin_password

  os_disk {
    name                 = "${lower(var.prefix)}-${count.index + 1}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }

  tags = {
    environment = var.prod
    source      = var.sourcedeployment
  }
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_virtual_machine 

# ------------------------------------------------------------
# 18) VM Extension: Domain Join
# ------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "domain_join" {
  count                      = var.rdsh_count
  name                       = "${var.prefix}-${count.index + 1}-domainJoin"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "Name": "${var.domain_name}",
      "OUPath": "${var.ou_path}",
      "User": "${var.domain_user_upn}@${var.domain_name}",
      "Restart": "true",
      "Options": "3"
    }
  SETTINGS

  protected_settings = <<-PROTECTED_SETTINGS
    {
      "Password": "${var.domain_password}"
    }
  PROTECTED_SETTINGS
}
# Docs: https://learn.microsoft.com/azure/virtual-machines/extensions/dsc-template#jsonaddomainextension 

# ------------------------------------------------------------
# 19) VM Extension: DSC for AVD Registration
# ------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count                      = var.rdsh_count
  name                       = "${var.prefix}-${count.index + 1}-avd_dsc"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.76"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName": "${azurerm_virtual_desktop_host_pool.hostpool.name}",
        "SessionHostName": "${azurerm_windows_virtual_machine.avd_vm[count.index].name}",
        "RegistrationInfoExpirationDate": "${azurerm_virtual_desktop_host_pool_registration_info.registrationinfo.expiration_date}"
      }
    }
  SETTINGS

  protected_settings = <<-PROTECTED_SETTINGS
    {
      "properties": {
        "registrationInfoToken": "${azurerm_virtual_desktop_host_pool_registration_info.registrationinfo.token}"
      }
    }
  PROTECTED_SETTINGS
}
# Docs: https://learn.microsoft.com/azure/developer/terraform/create-avd-session-host