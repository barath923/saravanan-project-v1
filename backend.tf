terraform {
  backend "azurerm" {
    resource_group_name  = "backend-state-files-rg"
    storage_account_name = "ramtfstate12345"   # must be unique globally, lowercase only
    container_name       = "tfstate"
    key                  = "./terraform.tfstate"
  }
}

