#-- Azure Variables
variable "prefix" {
  default     = "khlab"
  description = "Prefix for resource naming"
}

variable "resource_group_location" {
  default     = "uksouth"
  description = "Azure region for deployment"
}

variable "rg_vnet" {
  default     = "UK-LDN-vNet"
  description = "Name of the resource group"
}

variable "rg_servers" {
  default     = "UK-LDN-Servers"
  description = "Name of the resource group"
}

variable "rg" {
  default     = "UK-LDN-Servers-AVD"
  description = "Name of the resource group"
}

variable "rdsh_count" {
  default     = 4
  description = "Number of session hosts to deploy"
}

variable "vm_size" {
  default     = "Standard_B2ms"
  description = "VM size"
}

#-- Win Local Credentials
variable "local_admin_username" {
  default     = "localadm"
  description = "Local admin username"
}

variable "local_admin_password" {
  default   = "ChangeMe123!"
  sensitive = true
}

#-- Win Domain Credentials
variable "domain_name" {
  default = "ad.khlab.com"
}

variable "domain_user_upn" {
  default = "localadm"
}

variable "domain_password" {
  default   = "ChangeMe123!"
  sensitive = true
}

variable "ou_path" {
  default = "OU=AVD-Desktops,OU=Servers,OU=khlab,DC=ad,DC=khlab,DC=com"
}

#-- Other Variables
variable "registration_expiration" {
  default     = "2025-12-31T23:59:59Z"
  description = "Host pool registration token expiry in RFC3339 format"
}

variable "prod" {
  type        = string
  default     = "prod"
  description = "Prod Environment"
}

variable "dev" {
  type        = string
  default     = "dev"
  description = "Dev Environment"
}

variable "sourcedeployment" {
  type    = string
  default = "Terraform"
}
