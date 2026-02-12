resource "azurerm_resource_group" "dr" {
  name     = var.dr_resource_group_name
  location = var.dr_location
}

#############################
# DR Network (Target VNet)
#############################
resource "azurerm_virtual_network" "dr_vnet" {
  name                = var.dr_vnet_name
  location            = var.dr_location
  resource_group_name = azurerm_resource_group.dr.name
  address_space       = [var.dr_vnet_cidr]
}

resource "azurerm_subnet" "dr_mgmt" {
  name                 = var.dr_mgmt_subnet_name
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr_vnet.name
  address_prefixes     = [var.dr_mgmt_subnet_cidr]
}

resource "azurerm_subnet" "dr_shared" {
  name                 = var.dr_shared_subnet_name
  resource_group_name  = azurerm_resource_group.dr.name
  virtual_network_name = azurerm_virtual_network.dr_vnet.name
  address_prefixes     = [var.dr_shared_subnet_cidr]
}

#############################
# Recovery Services Vault
#############################
resource "azurerm_recovery_services_vault" "vault" {
  name                = var.recovery_vault_name
  location            = var.dr_location
  resource_group_name = azurerm_resource_group.dr.name
  sku                 = "Standard"
}

#############################
# Site Recovery Fabrics
#############################

# Primary fabric (source region)
resource "azurerm_site_recovery_fabric" "primary" {
  name                = "asr-fabric-primary"
  resource_group_name = azurerm_resource_group.dr.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  location            = var.source_location
}

# Secondary fabric (DR region)
# Note: Creating fabrics simultaneously can cause issues; dependency ordering helps. :contentReference[oaicite:5]{index=5}
resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "asr-fabric-secondary"
  resource_group_name = azurerm_resource_group.dr.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  location            = var.dr_location

  depends_on = [azurerm_site_recovery_fabric.primary]
}

#############################
# Protection Containers
#############################
resource "azurerm_site_recovery_protection_container" "primary" {
  name                 = "asr-container-primary"
  resource_group_name  = azurerm_resource_group.dr.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
}

resource "azurerm_site_recovery_protection_container" "secondary" {
  name                 = "asr-container-secondary"
  resource_group_name  = azurerm_resource_group.dr.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
}

#############################
# Replication Policy
#############################
resource "azurerm_site_recovery_replication_policy" "policy" {
  name                                                 = var.replication_policy_name
  resource_group_name                                  = azurerm_resource_group.dr.name
  recovery_vault_name                                  = azurerm_recovery_services_vault.vault.name
  recovery_point_retention_in_minutes                  = var.recovery_point_retention_minutes
  application_consistent_snapshot_frequency_in_minutes = var.app_consistent_snapshot_minutes
}

#############################
# Container Mapping (Primary -> Secondary)
#############################
resource "azurerm_site_recovery_protection_container_mapping" "mapping" {
  name                                      = "asr-container-mapping"
  resource_group_name                       = azurerm_resource_group.dr.name
  recovery_vault_name                       = azurerm_recovery_services_vault.vault.name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.primary.name
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.secondary.id
}

#############################
# Network Mapping (Source VNet -> DR VNet)
#############################
resource "azurerm_site_recovery_network_mapping" "netmap" {
  name                        = "asr-netmap-primary-to-dr"
  resource_group_name         = azurerm_resource_group.dr.name
  recovery_vault_name         = azurerm_recovery_services_vault.vault.name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
  source_network_id           = var.source_vnet_id
  target_network_id           = azurerm_virtual_network.dr_vnet.id
}

#############################
# Staging Storage Account (Source region) for replication
#############################
resource "random_string" "sa_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "staging" {
  # must be globally unique, 3-24 chars, lowercase only
  name                     = "asrstaging${random_string.sa_suffix.result}"
  resource_group_name      = var.source_resource_group_name
  location                 = var.source_location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  network_rules {
    default_action = "Allow"
  }
}

#############################
# Lookup OS Disk IDs by disk name
#############################
# data "azurerm_managed_disk" "osdisk" {
#   for_each            = var.vms
#   name                = each.value.os_disk_name
#   resource_group_name = var.source_resource_group_name
# }

data "azurerm_managed_disk" "osdisk" {
  for_each            = var.vms
  name                = each.value.os_disk_name
  resource_group_name = var.source_resource_group_name
}

#############################
# Replicate each VM
#############################
locals {
  # Build per-VM list of disk IDs = [os_disk_id] + data_disk_ids
  vm_disk_ids = {
    for vm_name, vm in var.vms : vm_name => concat(
      [data.azurerm_managed_disk.osdisk[vm_name].id],
      vm.data_disk_ids
    )
  }

#   #vm_disk_ids = {
#   for vm_name, vm in var.vms : vm_name => concat(
#     [vm.os_disk_id],
#     vm.data_disk_ids
#   )
# } 
}

resource "azurerm_site_recovery_replicated_vm" "replicated" {
  for_each = var.vms

  name                                      = "${each.key}-replication"
  resource_group_name                       = azurerm_resource_group.dr.name
  recovery_vault_name                       = azurerm_recovery_services_vault.vault.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  source_vm_id                              = each.value.vm_id

  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
  target_recovery_fabric_id                 = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id   = azurerm_site_recovery_protection_container.secondary.id
  target_resource_group_id                  = azurerm_resource_group.dr.id

  # Network interface mapping (choose DR subnet based on subnet_type)
  network_interface {
    source_network_interface_id = each.value.nic_id
    target_subnet_name          = each.value.subnet_type == "mgmt" ? azurerm_subnet.dr_mgmt.name : azurerm_subnet.dr_shared.name
  }

  # Disk mappings (OS + data disks)
  dynamic "managed_disk" {
    for_each = toset(local.vm_disk_ids[each.key])
    content {
      disk_id                    = managed_disk.value
      staging_storage_account_id = azurerm_storage_account.staging.id

      target_resource_group_id   = azurerm_resource_group.dr.id
      target_disk_type           = "Standard_LRS"
      target_replica_disk_type   = "Standard_LRS"
    }
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.mapping,
    azurerm_site_recovery_network_mapping.netmap
  ]
}
