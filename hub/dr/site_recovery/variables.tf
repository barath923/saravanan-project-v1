variable "source_location" {
  type        = string
  description = "Primary Azure region (source). Example: eastus"
}

variable "source_resource_group_name" {
  type        = string
  description = "Source RG where the VMs and disks exist"
}

variable "source_vnet_id" {
  type        = string
  description = "Source VNet ID (primary region) for ASR network mapping"
}

variable "dr_location" {
  type        = string
  description = "DR Azure region (target). Example: westus"
}

variable "dr_resource_group_name" {
  type        = string
  description = "DR RG name (target region)"
}

variable "dr_vnet_name" {
  type        = string
  description = "DR VNet name"
}

variable "dr_vnet_cidr" {
  type        = string
  description = "DR VNet CIDR"
}

variable "dr_mgmt_subnet_name" {
  type        = string
  description = "DR mgmt subnet name (should match your source naming style)"
}

variable "dr_mgmt_subnet_cidr" {
  type        = string
  description = "DR mgmt subnet CIDR"
}

variable "dr_shared_subnet_name" {
  type        = string
  description = "DR shared subnet name (should match your source naming style)"
}

variable "dr_shared_subnet_cidr" {
  type        = string
  description = "DR shared subnet CIDR"
}

variable "recovery_vault_name" {
  type        = string
  description = "Recovery Services Vault name"
}

variable "replication_policy_name" {
  type        = string
  description = "ASR replication policy name"
}

variable "recovery_point_retention_minutes" {
  type        = number
  description = "Recovery point retention in minutes (e.g., 1440 = 24 hours)"
  default     = 1440
}

variable "app_consistent_snapshot_minutes" {
  type        = number
  description = "Application consistent snapshot frequency in minutes (e.g., 240 = 4 hours)"
  default     = 240
}

variable "vms" {
  description = "VMs to enable DR replication for"
  type = map(object({
    vm_id        = string
    nic_id       = string
    subnet_type  = string         # 'mgmt' or 'shared'
    os_disk_name = string
    data_disk_ids = list(string)  # can be empty
  }))
}
