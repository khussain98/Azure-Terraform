#Useful commands
#terraform version
#terraform init
#terraform fmt
#terraform validate
#terraform plan
#terraform apply
#terraform apply -auto-approve
#terraform destroy

# Provides configuraiton details for Terraform
terraform {
required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "~>2.31.1"
    }
}
}

# Provides configuration details for the Azure Terraform provider
provider "azurerm"{
    features {}
}

# Provides the Resource Group to logically contain resources
resource "azurerm_resource_group" "rg" {
    name = "Example-Resource-Group"
    location = "UKSouth"
    tags = {
        environment = "dev"
        source = "terraform"
    }
}
