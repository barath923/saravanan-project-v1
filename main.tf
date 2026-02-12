#HUB RESOURCES

resource "azurerm_resource_group" "hub_resource_group" {
  name     = var.hub_resource_group_name
  location = var.hub_location
}

data "azurerm_client_config" "current" {}

module "hub_networking" {
  source              = "./hub/networking"
  hub_resource_group_name = azurerm_resource_group.hub_resource_group.name
  hub_location            = var.hub_location
  hub_vnet_name = "vnet-hub"
  hub_vnet_cidr = "172.20.0.0/24"
  hub_vnet_management_subnet_name = "hub-mgmtsubnet"
  hub_vnet_management_subnet_cidr = "172.20.0.0/27"

  hub_vnet_gateway_subnet_name = "GatewaySubnet"
  hub_vnet_gateway_subnet_cidr = "172.20.0.64/27"

  hub_vnet_shared_subnet_name = "hub-sharedsubnet"
  hub_vnet_shared_subnet_cidr = "172.20.0.32/27"

  hub_nat_gateway_name = "hub-shared-natgw"
  hub_nat_public_ip_name = "hub-shared-natgw-pip"
}

module "hub_compute" {
  source              = "./hub/compute"
  resource_group_name = azurerm_resource_group.hub_resource_group.name
  location            = var.hub_location

  vms      = var.hub_vms
  jumpvms  = var.hub_jumpvms

  subnet_mgmt_id   = module.hub_networking.subnet_mgmt_id
  subnet_shared_id = module.hub_networking.subnet_shared_id
}

module "hub_extensions" {
  source   = "./hub/extensions"
  vms      = var.hub_vms
  jumpvms  = var.hub_jumpvms
  windows_vm_ids = module.hub_compute.windows_vm_ids
  linux_vm_ids   = module.hub_compute.linux_vm_ids
  location_map   = module.hub_compute.location_map
}

###DR FOR HUB RESOURCES

locals {

  all_vm_cfg = merge(var.hub_vms, var.hub_jumpvms)

  all_vm_ids = merge(
    module.hub_compute.windows_vm_ids,
    module.hub_compute.linux_vm_ids
  )

  # Build a single VM object map that DR module can consume
  # dr_vms = {
  #   for vm_name, vm_id in local.all_vm_ids : vm_name => {
  #     vm_id       = local.all_vm_ids[vm_name]
  #     nic_id      = module.hub_compute.vm_nic_ids[vm_name]
  #     subnet_type = module.hub_compute.vm_subnet_types[vm_name]
  #     os_disk_name = module.hub_compute.vm_os_disk_names[vm_name]
  #     #os_disk_id = module.hub_compute.vm_os_disk_ids[vm_name]

  #     # If windows VM has a 10GB disk, pass it, else empty list
  #     # data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name)
  #     #   ? [module.hub_compute.windows_data_disk_ids[vm_name]]
  #     #   : []
  #     # data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name) ? [module.hub_compute.windows_data_disk_ids[vm_name]] : []
  #     data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name) ? [module.hub_compute.windows_data_disk_ids[vm_name]] : []
  #   }
  # }

  dr_vms = {
    for vm_name, cfg in local.all_vm_cfg : vm_name => {
      vm_id       = local.all_vm_ids[vm_name]
      nic_id      = module.hub_compute.vm_nic_ids[vm_name]
      subnet_type = cfg.subnet_type
      os_disk_name = module.hub_compute.vm_os_disk_names[vm_name]
      #os_disk_id = module.hub_compute.vm_os_disk_ids[vm_name]

      # If windows VM has a 10GB disk, pass it, else empty list
      # data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name)
      #   ? [module.hub_compute.windows_data_disk_ids[vm_name]]
      #   : []
      # data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name) ? [module.hub_compute.windows_data_disk_ids[vm_name]] : []
      data_disk_ids = contains(keys(module.hub_compute.windows_data_disk_ids), vm_name) ? [module.hub_compute.windows_data_disk_ids[vm_name]] : []
    }
  }
}

module "dr_site_recovery" {
  source = "./hub/dr/site_recovery"

  # Source (primary) 
  source_location            = var.hub_location
  source_resource_group_name = azurerm_resource_group.hub_resource_group.name
  source_vnet_id             = module.hub_networking.hub_vnet_id

  # Target (secondary / DR)
  dr_location                = var.dr_location
  dr_resource_group_name     = var.dr_resource_group_name

  # DR network (create new in DR region)
  dr_vnet_name                    = "hub-vnet-dr"
  dr_vnet_cidr                    = "172.30.0.0/24"
  dr_mgmt_subnet_name             = "hub-mgmtsubnet"
  dr_mgmt_subnet_cidr             = "172.30.0.0/27"
  dr_shared_subnet_name           = "hub-sharedsubnet"
  dr_shared_subnet_cidr           = "172.30.0.32/27"

  # Vault & policy
  recovery_vault_name             = "rsv-hub-dr"
  replication_policy_name         = "vm-dr-policy"
  recovery_point_retention_minutes = 1440  # 24 hours
  app_consistent_snapshot_minutes  = 240   # 4 hours

  # VMs to protect
  vms = local.dr_vms
}








#CLINICAL RESOURCES

resource "azurerm_resource_group" "clinical_resource_group" {
  name     = var.clinical_resource_group_name
  location = var.clinical_location
}

module "clinical_networking" {
  source              = "./clinical/networking"
  clinical_resource_group_name = azurerm_resource_group.clinical_resource_group.name
  clinical_location            = var.clinical_location

  clinical_vnet_name = "vnet-clinical"
  clinical_vnet_cidr = "172.20.2.0/24"
  
  clinical_vnet_management_subnet_name = "clinical-mgmtsubnet"
  clinical_vnet_management_subnet_cidr = "172.20.2.128/27"

  clinical_vnet_subnet_one_name = "clinical-sharedsubnet-1"
  clinical_vnet_shared_one_cidr = "172.20.2.160/27"

  clinical_vnet_shared_two_name = "clinical-sharedsubnet-2"
  clinical_vnet_shared_two_cidr = "172.20.2.192/26"

  clinical_nat_gateway_name = "clinical-shared-natgw"
  clinical_nat_public_ip_name = "clinical-shared-natgw-pip"
}

module "clinical_compute" {
  source                       = "./clinical/compute"
  clinical_resource_group_name = azurerm_resource_group.clinical_resource_group.name
  clinical_location            = var.clinical_location

  vms      = var.clinical_vms
  jumpvms  = var.clinical_jumpvms
  management_subnet_id       = module.clinical_networking.management_subnet_id
  subnet_one_id              = module.clinical_networking.subnet_one_id
  subnet_two_id              = module.clinical_networking.subnet_two_id
}

module "clinical_extensions" {
  source   = "./clinical/extensions"
  vms      = var.clinical_vms
  jumpvms  = var.clinical_jumpvms
  windows_vm_ids = module.clinical_compute.windows_vm_ids
  linux_vm_ids   = module.clinical_compute.linux_vm_ids
  location_map   = module.clinical_compute.location_map
}

#NON - CLINICAL RESOURCES

resource "azurerm_resource_group" "non_clinical_resource_group" {
  name     = var.non_clinical_resource_group_name
  location = var.non_clinical_location
}

module "non_clinical_networking" {
  source              = "./non_clinical/networking"
  non_clinical_resource_group_name = azurerm_resource_group.non_clinical_resource_group.name
  non_clinical_location            = var.non_clinical_location

  non_clinical_vnet_name = "vnet-non-clinical"
  non_clinical_vnet_cidr = "172.20.3.0/24"
  
  non_clinical_vnet_management_subnet_name = "non-clinical-mgmtsubnet"
  non_clinical_vnet_management_subnet_cidr = "172.20.3.128/27"

  non_clinical_vnet_subnet_one_name = "non-clinical-sharedsubnet-1"
  non_clinical_vnet_shared_one_cidr = "172.20.3.160/27"

  non_clinical_vnet_shared_two_name = "non-clinical-sharedsubnet-2"
  non_clinical_vnet_shared_two_cidr = "172.20.3.192/26"
}

module "non_clinical_compute" {
  source                       = "./non_clinical/compute"
  non_clinical_resource_group_name = azurerm_resource_group.non_clinical_resource_group.name
  non_clinical_location            = var.non_clinical_location

  vms      = var.non_clinical_vms
  jumpvms  = var.non_clinical_jumpvms
  management_subnet_id       = module.non_clinical_networking.management_subnet_id
  subnet_one_id              = module.non_clinical_networking.subnet_one_id
  subnet_two_id              = module.non_clinical_networking.subnet_two_id
}

module "non_clinical_extensions" {
  source   = "./non_clinical/extensions"
  vms      = var.non_clinical_vms
  jumpvms  = var.non_clinical_jumpvms
  windows_vm_ids = module.non_clinical_compute.windows_vm_ids
  linux_vm_ids   = module.non_clinical_compute.linux_vm_ids
  location_map   = module.non_clinical_compute.location_map
}


#VELOCITY RESOURCES

resource "azurerm_resource_group" "velocity_resource_group" {
  name     = var.velocity_resource_group_name
  location = var.velocity_location
}

module "velocity_networking" {
  source              = "./velocity/networking"
  velocity_resource_group_name = azurerm_resource_group.velocity_resource_group.name
  velocity_location            = var.velocity_location

  velocity_vnet_name = "vnet-velocity"
  velocity_vnet_cidr = "172.20.4.0/24"
  
  velocity_vnet_management_subnet_name = "velocity-mgmtsubnet"
  velocity_vnet_management_subnet_cidr = "172.20.4.96/28"

  velocity_vnet_subnet_one_name = "velocity-sharedsubnet-1"
  velocity_vnet_shared_one_cidr = "172.20.4.112/28"
}

module "velocity_compute" {
  source                       = "./velocity/compute"
  velocity_resource_group_name = azurerm_resource_group.velocity_resource_group.name
  velocity_location            = var.velocity_location
  vms                          = var.velocity_vms
  jumpvms                      = var.velocity_jumpvms
  management_subnet_id       = module.velocity_networking.management_subnet_id
  subnet_one_id              = module.velocity_networking.subnet_one_id
}

module "velocity_extensions" {
  source   = "./velocity/extensions"
  vms      = var.velocity_vms
  jumpvms  = var.velocity_jumpvms
  windows_vm_ids = module.velocity_compute.windows_vm_ids
  linux_vm_ids   = module.velocity_compute.linux_vm_ids
  location_map   = module.velocity_compute.location_map
}


#GATEWAY RESOURCES

resource "azurerm_resource_group" "gateway_resource_group" {
  name     = var.gateway_resource_group_name
  location = var.gateway_location
}

module "gateway_networking" {
  source                      = "./gateway/networking"

  gateway_resource_group_name = azurerm_resource_group.gateway_resource_group.name
  gateway_location            = azurerm_resource_group.gateway_resource_group.location

  gateway_vnet_name = "vnet-gateway"
  gateway_vnet_cidr = "172.22.0.0/24"

  gateway_vnet_panmanagement_subnet_name = "gateway-mgmtsubnet"
  gateway_vnet_panmanagement_subnet_cidr = "172.22.0.16/29"

  gateway_vnet_pantrust_subnet_name = "gateway-trustsubnet"
  gateway_vnet_pantrust_subnet_cidr = "172.22.0.24/29"
  
  gateway_vnet_panuntrust_subnet_name = "gateway-untrustsubnet"
  gateway_vnet_panuntrust_subnet_cidr = "172.22.0.32/29" 
  
  gateway_vnet_gateway_subnet_name = "gateway-subnet"
  gateway_vnet_gateway_subnet_cidr = "172.22.0.64/27"

  gateway_vnet_pancustom_subnet_name = "gateway-pancustomsubnet"
  gateway_vnet_pancustom_subnet_cidr = "172.22.0.128/25"

  gateway_vnet_pandev_subnet_name = "gateway-pandev"
  gateway_vnet_pandev_subnet_cidr = "172.22.0.8/29"
}


module "gateway_compute" {
  source                      = "./gateway/compute"

  gateway_resource_group_name = azurerm_resource_group.gateway_resource_group.name
  gateway_location            = azurerm_resource_group.gateway_resource_group.location
  pan_mgmt_subnet_id          = module.gateway_networking.pan_mgmt_subnet_id
  pan_trust_subnet_id      = module.gateway_networking.pan_trust_subnet_id
  pan_untrust_subnet_id    = module.gateway_networking.pan_untrust_subnet_id
  gateway_subnet_id        = module.gateway_networking.gateway_subnet_id
  pan_custom_subnet_id     = module.gateway_networking.pan_custom_subnet_id
  pan_dev_subnet_id        = module.gateway_networking.pan_dev_subnet_id 

}


# peerings hub and spoke

module "hub_and_spokes_peering" {
  source = "./peering"
  
  #hub
  hub_resource_group_name     = azurerm_resource_group.hub_resource_group.name
  hub_vnet_id                 = module.hub_networking.hub_vnet_id
  hub_location                = var.hub_location
  hub_vnet_name               = module.hub_networking.hub_vnet_name  
  #hub subnets
  hub_subnet_mgmt_id          = module.hub_networking.subnet_mgmt_id
  hub_subnet_shared_id        = module.hub_networking.subnet_shared_id
  hub_subnet_gateway_id       = module.hub_networking.hub_subnet_gateway_id 

  #gateway
  gateway_resource_group_name     = azurerm_resource_group.gateway_resource_group.name
  gateway_vnet_id                 = module.gateway_networking.gateway_vnet_id
  gateway_location                = var.gateway_location
  gateway_vnet_name               = module.gateway_networking.gateway_vnet_name
  #gateway Subnets
  pan_mgmt_subnet_id       = module.gateway_networking.pan_mgmt_subnet_id
  pan_trust_subnet_id      = module.gateway_networking.pan_trust_subnet_id
  pan_untrust_subnet_id    = module.gateway_networking.pan_untrust_subnet_id
  pan_gateway_subnet_id    = module.gateway_networking.gateway_subnet_id
  pan_custom_subnet_id     = module.gateway_networking.pan_custom_subnet_id
  pan_dev_subnet_id        = module.gateway_networking.pan_dev_subnet_id

  #velocity
  velocity_resource_group_name        = azurerm_resource_group.velocity_resource_group.name
  velocity_vnet_id                    = module.velocity_networking.velocity_vnet_id
  velocity_location                   = var.velocity_location
  velocity_vnet_name                  = module.velocity_networking.velocity_vnet_name
  #velocity subnets
  velocity_management_subnet_id       = module.velocity_networking.management_subnet_id
  velocity_subnet_one_id              = module.velocity_networking.subnet_one_id

  #clinical
  clinical_resource_group_name     = azurerm_resource_group.clinical_resource_group.name
  clinical_vnet_id                 = module.clinical_networking.clinical_vnet_id
  clinical_location                = var.clinical_location
  clinical_vnet_name               = module.clinical_networking.clinical_vnet_name
  #clinical subnets
  clinical_management_subnet_id       = module.clinical_networking.management_subnet_id
  clinical_subnet_one_id              = module.clinical_networking.subnet_one_id
  clinical_subnet_two_id              = module.clinical_networking.subnet_two_id

  #non clinical
  non_clinical_resource_group_name     = azurerm_resource_group.non_clinical_resource_group.name
  non_clinical_vnet_id                 = module.non_clinical_networking.non_clinical_vnet_id
  non_clinical_location                = var.non_clinical_location
  non_clinical_vnet_name               = module.non_clinical_networking.non_clinical_vnet_name
  #non clinical subnets
  non_clinical_management_subnet_id       = module.non_clinical_networking.management_subnet_id
  non_clinical_subnet_one_id              = module.non_clinical_networking.subnet_one_id
  non_clinical_subnet_two_id              = module.non_clinical_networking.subnet_two_id 
}