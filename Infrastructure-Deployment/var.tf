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
