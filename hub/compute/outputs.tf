# OUTPUTS
output "windows_vm_ids" {
  value = {
    for k, v in azurerm_windows_virtual_machine.windows :
    k => v.id
  }
}

output "linux_vm_ids" {
  value = {
    for k, v in azurerm_linux_virtual_machine.linux :
    k => v.id
  }
}

output "location_map" {
  value = {
    for k, v in local.all_vms_map :
    k => v.location
  }
}

output "vm_nic_ids" {
  value = {
    for k, v in azurerm_network_interface.nic :
    k => v.id
  }
}

output "vm_subnet_types" {
  value = {
    for k, v in local.all_vms_map :
    k => v.subnet_type
  } 
}

output "vm_os_disk_names" {
  value = merge(
    { for k, v in azurerm_windows_virtual_machine.windows : k => v.os_disk[0].name },
    { for k, v in azurerm_linux_virtual_machine.linux   : k => v.os_disk[0].name }
  )
}

# output "vm_os_disk_ids" {
#   value = merge(
#     { for k, v in azurerm_windows_virtual_machine.windows : k => v.os_disk[0].managed_disk_id },
#     { for k, v in azurerm_linux_virtual_machine.linux   : k => v.os_disk[0].managed_disk_id }
#   )
# }

output "windows_data_disk_ids" {
  value = try(
    {
      for k, v in azurerm_managed_disk.windows_data_disk_10gb :
      k => v.id
    },
    {}
  )
}
