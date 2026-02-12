output "dr_resource_group_id" {
  value = azurerm_resource_group.dr.id
}

output "recovery_vault_id" {
  value = azurerm_recovery_services_vault.vault.id
}

output "dr_vnet_id" {
  value = azurerm_virtual_network.dr_vnet.id
}

output "replicated_vm_ids" {
  value = {
    for k, v in azurerm_site_recovery_replicated_vm.replicated :
    k => v.id
  }
}
