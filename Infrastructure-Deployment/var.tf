# Internal Prefix Naming Convention
variable "prefix" {
  type    = string
  default = "khlab"
}

# vNet Subnet Space
variable "addressprefix" {
  type    = list(string)
  default = ["192.168.0.0/16"]
}

# Azure Internal Subnet
variable "addressprefixazure" {
  type    = list(string)
  default = ["192.168.2.0/24"]
}

variable "name" {
  type    = string
  default = "createdusingtf"
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
