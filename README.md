# Project Documentation

This project is a **Terraform infrastructure** for Azure.
It builds a **hub-and-spoke network** with five environments:

- **Hub** (central network + shared services)
- **Gateway** (security/edge routing VM)
- **Clinical** spoke
- **Non-Clinical** spoke
- **Velocity** spoke

It also configures:

- VM deployment in each environment
- VM post-deployment extensions
- Cross-VNet peering and routing
- Disaster Recovery (DR) for hub VMs using Azure Site Recovery
- Remote Terraform state in Azure Storage

---

![image](https://github.com/barath923/saravanan-project-v1/blob/334bc7f8ccd706298de2ecc24baaeac1b5b21462/HUB%26SPOKE.jpg)

---

## 1) Root-level files

## `backend.tf`
Defines where Terraform state is stored remotely (Azure Storage backend).

- Resource group: `backend-state-files-rg`
- Storage account: `ramtfstate12345`
- Container: `tfstate`
- State key: `./terraform.tfstate`

Why it matters: team members share one source of truth for infrastructure state.

## `main.tf`
This is the main orchestrator. It:

1. Creates resource groups for each environment.
2. Calls networking modules.
3. Calls compute modules.
4. Calls extensions modules.
5. Builds DR input maps and calls the DR module.
6. Calls the peering module to connect all VNets and apply route tables.

## `variable.tf`
Defines all input variables.

Most VM inputs are maps of VM objects, with fields like:

- `os_type` (`windows` or `linux`)
- `vm_size`
- image settings (`publisher`, `offer`, `sku`, `version`)
- `subnet_type`
- `attach_public_ip`
- `private_ip`

## `terraform.tfvars`
Provides actual values used for deployment.

Includes:

- Region names and resource group names
- Sample/active VM definitions
- Many optional VM examples are currently commented out

## `outputs.tf`
Currently empty.

---

## 2) Overall architecture

Think of this setup as a central office and branch offices:

- **Hub VNet** is the central office.
- **Clinical / Non-Clinical / Velocity VNets** are branch networks.
- **Gateway VNet** hosts a routing/security VM (Palo Alto style topology).
- **Peering** connects the hub with each spoke.
- **Route tables** make traffic go through the virtual network gateway path.

The hub also has a **DR copy** in another region with Azure Site Recovery.

---

## 3) Module-by-module explanation

## A) Hub modules

### `hub/networking`
Creates:

- Hub VNet
- Management subnet
- Shared subnet
- Gateway subnet
- NAT gateway + public IP
- NAT association to the shared subnet

Simple meaning: builds the core network and outbound internet path for shared workloads.

### `hub/compute`
Creates:

- NSGs for management and shared workloads
- NICs for all VMs
- Optional public IPs
- Windows and Linux VMs based on input maps
- A 10GB managed data disk attached to Windows VMs

Simple meaning: this module converts VM definitions into actual VMs and network wiring.

### `hub/extensions`
Adds VM extensions after VM creation:

- Validates timezone values
- Applies timezone setup for jump VMs
- Applies Linux custom script extensions for software/timezone setup

Simple meaning: does post-provision configuration so VMs are usable without manual setup.

### `hub/dr/site_recovery`
Creates DR resources and replication policies:

- DR resource group + DR VNet + DR subnets
- Recovery Services vault
- Site Recovery fabrics, containers, mappings
- Replication policy (retention and app-consistent snapshot schedule)
- Staging storage account
- Replication of selected hub VMs

Simple meaning: if primary region fails, replicated VMs are ready in DR region.

---

## B) Clinical modules

### `clinical/networking`
Creates clinical VNet with 3 subnets (management + two shared subnets) and NAT gateways for the shared subnets.

### `clinical/compute`
Creates clinical NSGs, NICs, optional public IPs, and Windows/Linux VMs.

### `clinical/extensions`
Applies timezone/software extensions similarly to hub extensions.

Simple meaning: same pattern as hub, but scoped to clinical environment.

---

## C) Non-Clinical modules

### `non_clinical/networking`
Creates non-clinical VNet, 3 subnets, NAT gateways, and associations.

### `non_clinical/compute`
Creates NSGs, NICs, public IPs, and VMs.

### `non_clinical/extensions`
Applies post-deployment VM extensions.

Simple meaning: mirrored environment for non-clinical workloads.

---

## D) Velocity modules

### `velocity/networking`
Creates velocity VNet with management + one shared subnet and NAT for the shared subnet.

### `velocity/compute`
Creates NSGs, NICs, optional public IPs, and VMs.

### `velocity/extensions`
Applies timezone/software VM extension steps.

Simple meaning: lightweight spoke compared to clinical/non-clinical.

---

## E) Gateway modules

### `gateway/networking`
Creates gateway VNet and multiple subnets:

- PAN management
- PAN trust
- PAN untrust
- gateway subnet
- PAN custom
- PAN dev

Simple meaning: network layout prepared for a security/routing appliance.

### `gateway/compute`
Creates:

- Public IP for management NIC
- NSG for management access
- Multiple NICs (mgmt/trust/untrust)
- Linux VM with multiple NICs (acts as gateway/firewall VM)

Simple meaning: deploys the central security/routing VM.

---

## F) `peering` module

This module ties the whole environment together.

It creates:

1. Hub VPN public IP + virtual network gateway.
2. Route tables for gateway, velocity, clinical, non-clinical.
3. Route table associations on selected subnets.
4. Bidirectional VNet peering between hub and each spoke (gateway, velocity, clinical, non-clinical).

Simple meaning: network connectivity + routing policy are centralized here.

---

## 4) Important data flow between modules

- Root `main.tf` passes subnet IDs from networking modules to compute modules.
- Compute modules output VM IDs and metadata.
- Extensions modules consume VM IDs and VM metadata.
- Hub compute outputs feed DR module via a transformed local map (`local.dr_vms`).
- All VNet IDs/subnet IDs flow into peering module for routing and peering setup.

---

## 7) One-line summary

This Terraform project builds a multi-environment Azure hub-and-spoke platform with VM workloads, shared networking, centralized routing/peering, and hub disaster recovery replication.
