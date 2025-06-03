# ------------------------------------------------------------
# 1) Provider Configuration
# ------------------------------------------------------------
#already defined in providers.tf

# ------------------------------------------------------------
# 2) Locals
# ------------------------------------------------------------
locals {
  # Pull the registration token from the host pool registration info resource
  registration_token = azurerm_virtual_desktop_host_pool_registration_info.registrationinfo.token
}

# ------------------------------------------------------------
# 3) Resource Group
# ------------------------------------------------------------
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
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network

resource "azurerm_subnet" "subnet" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.10.0/24"]
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet

# ------------------------------------------------------------
# 5) AVD Host Pool
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool" "hostpool" {
  name                 = "${var.prefix}-hostpool"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  type                 = "Pooled"                # or "Personal"
  load_balancer_type   = "BreadthFirst"          # Possible: "BreadthFirst", "DepthFirst", "Persistent"
  friendly_name        = "${var.prefix} Host Pool"
  validate_environment = true

  # If you want to define a registration_info block here instead of a separate resource:
  # registration_info {
  #   expiration_date = var.registration_expiration
  # }
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool

# ------------------------------------------------------------
# 6) AVD Application Group
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_application_group" "dag" {
  name                = "${var.prefix}-dag"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  host_pool_id        = azurerm_virtual_desktop_host_pool.hostpool.id
  type                = "Desktop"         # or "RemoteApp"
  friendly_name       = "${var.prefix} Application Group"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_application_group

# ------------------------------------------------------------
# 7) AVD Workspace & Association
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
# 8) Host Pool Registration Info (token for DSC registration)
# ------------------------------------------------------------
resource "azurerm_virtual_desktop_host_pool_registration_info" "registrationinfo" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.hostpool.id
  expiration_date = var.registration_expiration  # e.g. "2025-12-01T00:00:00Z"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_host_pool_registration_info

# ------------------------------------------------------------
# 9) Random String for local VM passwords
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
# 10) Network Interfaces for Session Hosts
# ------------------------------------------------------------
resource "azurerm_network_interface" "avd_vm_nic" {
  count               = var.rdsh_count
  name                = "${var.prefix}-${count.index + 1}-nic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "nic${count.index + 1}_config"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_interface

# ------------------------------------------------------------
# 11) Windows Virtual Machines (Session Hosts)
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
  offer     = "windows-11" #"Windows-10"
  sku       = "win11-21h2-avd" #"20h2-evd"
  version   = "latest"
}

}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/windows_virtual_machine

# ------------------------------------------------------------
# 12) VM Extension: Domain Join
# ------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "domain_join" {
  count                = var.rdsh_count
  name                 = "${var.prefix}-${count.index + 1}-domainJoin"
  virtual_machine_id   = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "JsonADDomainExtension"
  type_handler_version = "1.3"
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
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_machine_extension#jsonaddomainextension

# ------------------------------------------------------------
# 13) VM Extension: DSC for AVD Registration
# ------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "vmext_dsc" {
  count                = var.rdsh_count
  name                 = "${var.prefix}-${count.index + 1}-avd_dsc"
  virtual_machine_id   = azurerm_windows_virtual_machine.avd_vm[count.index].id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.73"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02714.342.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName": "${azurerm_virtual_desktop_host_pool.hostpool.name}"
      }
    }
  SETTINGS

  protected_settings = <<-PROTECTED_SETTINGS
    {
      "properties": {
        "registrationInfoToken": "${local.registration_token}"
      }
    }
  PROTECTED_SETTINGS
}
# Docs: https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/dsc-template
#      (see “Azure Virtual Desktop session host registration” examples)

# ------------------------------------------------------------
# 14) Storage Account + File Shares for FSLogix/MSIX
# ------------------------------------------------------------
resource "azurerm_storage_account" "avd_storage" {
  name                     = "${var.prefix}storage"  # Storage account names must be lowercase and 3-24 chars
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"
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
# 15) Azure AD Groups for AVD Admins & Users
# ------------------------------------------------------------
resource "azuread_group" "avd_admins" {
  display_name     = "AVDAdmin"
  security_enabled = true
}
# Docs: https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group

resource "azuread_group" "avd_users" {
  display_name     = "AVDUsers"
  security_enabled = true
}

# ------------------------------------------------------------
# 16) Role Definitions & Assignments
# ------------------------------------------------------------
data "azurerm_role_definition" "desktop_virtualization_user" {
  name = "Desktop Virtualization User"
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition

resource "azurerm_role_assignment" "avd_users_assignment" {
  scope              = azurerm_virtual_desktop_application_group.dag.id
  role_definition_id = data.azurerm_role_definition.desktop_virtualization_user.id
  principal_id       = azuread_group.avd_users.id
}
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment

data "azurerm_role_definition" "desktop_virtualization_admin" {
  name = "Desktop Virtualization Administrator"
}

resource "azurerm_role_assignment" "avd_admins_assignment" {
  scope              = azurerm_virtual_desktop_host_pool.hostpool.id
  role_definition_id = data.azurerm_role_definition.desktop_virtualization_admin.id
  principal_id       = azuread_group.avd_admins.id
}

# ------------------------------------------------------------
# 17) AVD Scaling Plan
# ------------------------------------------------------------
/**
resource "azurerm_virtual_desktop_scaling_plan" "scaling_plan" {
  name                = "${var.prefix}-scalingplan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  time_zone           = "GMT Standard Time"
  description         = "Scaling plan for AVD host pool"
  friendly_name       = "${var.prefix} Scaling Plan"

  schedule {
    name                             = "WeekdaySchedule"
    days_of_week                     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    # RAMP-UP phase: when VMs should start before peak
    ramp_up_start_time               = "08:00"
    ramp_up_load_balancing_algorithm = "BreadthFirst"
    ramp_up_minimum_hosts_percent    = 100
    ramp_up_capacity_threshold_pct   = 80

    # PEAK phase: active hours
    peak_start_time                  = "09:00"
    peak_load_balancing_algorithm    = "BreadthFirst"
    peak_minimum_hosts_percent       = 100
    peak_capacity_threshold_pct      = 90

    # RAMP-DOWN phase: when to start removing hosts after peak
    ramp_down_start_time                = "17:00"
    ramp_down_load_balancing_algorithm  = "DepthFirst"
    ramp_down_minimum_hosts_percent     = 25
    ramp_down_capacity_threshold_pct    = 60
    ramp_down_wait_time_minutes         = 15
    ramp_down_force_logoff_users        = true
    ramp_down_notification_message      = "Your session will log off soon due to scheduled maintenance."

    # OFF-PEAK phase: truly minimal hosts
    off_peak_start_time                = "18:00"
    off_peak_load_balancing_algorithm  = "DepthFirst"
    off_peak_minimum_hosts_percent     = 0
  }

  host_pool {
    hostpool_id          = azurerm_virtual_desktop_host_pool.hostpool.id
    scaling_plan_enabled = true
  }
}
**/
# Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_desktop_scaling_plan
