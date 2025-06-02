# Internal Prefix Naming Convention
variable "prefix" {
  type    = string
  default = "khlab"
}

# vNet Subnet Space
variable "addressprefix" {
  description = "Address Spaces for Azure"
  type = object({
    default = string
    azuuresubnet1 = string
    serversubnet1 = string
    websubnet1 = string
  })
  default = {
    default = ["192.168.0.0/16"]
    azuresubnet1 = ["192.168.20.0/24"]
    serversubnet1 = ["192.168.30.0/24"]
    websubnet1 = ["192.168.40.0/24"]
  }
}

# UK South Location
variable "location1" {
  type    = string
  default = "uksouth"
}

#--Strings
variable "test" {
  type    = string
  default = ""
}

variable "default_linux_creds" {
  description = "Default admin credentials for Linux VMs"
  type = object({
    username = string
    password = string
  })
  default = {
    username = "linuxadmin"
    password = "P@ssw0rd123!"
  }
}

variable "default_win_creds" {
  description = "Default admin credentials for Windows VMs"
  type = object({
    username = string
    password = string
  })
  default = {
    username = "winadmin"
    password = "P@ssw0rd123!"
  }
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
