locals {
  # lernmaas erkennen über den Provider-Teil des Workspace-Namens
  is_lernmaas = local.cloud_provider == "lernmaas"

  # Standard: einzelne VM "vm" (nicht lernmaas)
  vm_ip   = local.is_lernmaas ? null : try(module.vms.ip_vm["vm"], null)
  vm_fqdn = local.is_lernmaas ? null : try(module.vms.fqdn_vm["vm"], null)

  # lernmaas: Liste aller FQDNs aus module.vms.fqdn_vm
  vm_list = local.is_lernmaas ? [
    for k, v in module.vms.fqdn_vm : v
  ] : []
}

# Standard-README (alle Provider ausser lernmaas)
output "README" {
  value = local.is_lernmaas ? null : templatefile("INTRO.md", {
    vm_ip   = local.vm_ip
    vm_fqdn = local.vm_fqdn
    modul   = local.modul   # Suffix aus Workspace, z.B. "m122"
  })
}

# Spezielles README für lernmaas (Liste von VMs)
output "README_lernmaas" {
  value = local.is_lernmaas ? templatefile("INTRO_lernmaas.md", {
    vms   = local.vm_list   # Liste von FQDNs
    modul = local.modul
  }) : null
}
