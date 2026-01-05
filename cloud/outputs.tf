locals {
  # lernmaas erkennen über den Provider-Teil des Workspace-Namens
  is_lernmaas = local.cloud_provider == "lernmaas"

  # Standard: einzelne VM "vm" (nicht lernmaas)
  vm_ip   = local.is_lernmaas ? null : try(module.vms.ip_vm["vm"], null)
  vm_fqdn = local.is_lernmaas ? null : try(module.vms.fqdn_vm["vm"], null)

  # lernmaas: Liste aller FQDNs (nach Key sortiert, damit Reihenfolge stabil ist)
  vm_list = local.is_lernmaas ? [
    for k in sort(keys(module.vms.fqdn_vm)) : module.vms.fqdn_vm[k]
  ] : []

  # lernmaas: Liste aller IPs als list(string)
  # hier nehmen wir jeweils das erste Element aus dem Set
  ip_list = local.is_lernmaas ? [
    for k in sort(keys(module.vms.ip_vm)) : tolist(module.vms.ip_vm[k])[0]
  ] : []
}

# Standard-README (alle Provider ausser lernmaas)
output "README" {
  value = local.is_lernmaas ? null : templatefile("INTRO.md", {
    vm_ip   = local.vm_ip
    vm_fqdn = local.vm_fqdn
    modul   = local.modul
  })
}

# Spezielles README für lernmaas (Liste von VMs)
output "README_lernmaas" {
  value = local.is_lernmaas ? templatefile("INTRO_lernmaas.md", {
    ips   = local.ip_list
    vms   = local.vm_list
    modul = local.modul
  }) : null
}
