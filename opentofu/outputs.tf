locals {
  # einfacher Lernmaas-Schalter
  is_lernmaas = terraform.workspace == "lernmaas"

  # Standard-FQDN/IP (einzelne VMs)
  dev_ip   = try(module.vms.ip_vm["dev"], null)
  dev_fqdn = try(module.vms.fqdn_vm["dev"], null)

  vm_ip   = try(module.vms.ip_vm["vm"], null)
  vm_fqdn = try(module.vms.fqdn_vm["vm"], null)

  # Für lernmaas: mehrere VMs nach Präfix auswählen (dev-*, vm-*)
  dev_list = local.is_lernmaas ? [
    for k, v in module.vms.fqdn_vm : v if can(regex("^dev-", k))
  ] : [local.dev_fqdn]

  vm_list = local.is_lernmaas ? [
    for k, v in module.vms.fqdn_vm : v if can(regex("^vm-", k))
  ] : [local.vm_fqdn]
}

# Standard-README (alle Workspaces ausser lernmaas)
output "README" {
  value = local.is_lernmaas ? null : templatefile("INTRO.md", {
    development_ip   = local.dev_ip
    development_fqdn = local.dev_fqdn

    vm_ip   = local.vm_ip
    vm_fqdn = local.vm_fqdn
  })
}

# Spezielles README für Workspace lernmaas (mit Listen)
output "README_lernmaas" {
  value = local.is_lernmaas ? templatefile("INTRO_lernmaas.md", {
    devs = local.dev_list
    vms  = local.vm_list
  }) : null
}
