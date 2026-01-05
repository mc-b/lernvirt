terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "http" {}
provider "local" {}

# Aufteilen: lokale Datei vorhanden vs. Remote (Modulname)
locals {
  machines_local = {
    for name, m in local.machines_raw :
    name => m
    if can(file("${path.root}/${m.userdata}"))
  }

  machines_remote = {
    for name, m in local.machines_raw :
    name => m
    if !can(file("${path.root}/${m.userdata}"))
  }
}

# HTTP-Fallback für "remote"-Maschinen (userdata = Modulname)

data "http" "userdata_master" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/tbz-it/${each.value.userdata}/refs/heads/master/cloud-init.yaml"
}

data "http" "userdata_main" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/tbz-it/${each.value.userdata}/refs/heads/main/cloud-init.yaml"
}

data "http" "userdata_fallback" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml"
}

# Inhalte zusammenbauen (immer: String, kein Pfad)
locals {
  userdata_local = {
    for name, m in local.machines_local :
    # wenn du templating brauchst: templatefile("${path.root}/${m.userdata}", {})
    name => file("${path.root}/${m.userdata}")
  }

  userdata_remote = {
    for name, m in local.machines_remote :
    name =>
      data.http.userdata_master[name].status_code == 200
      ? data.http.userdata_master[name].response_body
      : data.http.userdata_main[name].status_code == 200
        ? data.http.userdata_main[name].response_body
        : data.http.userdata_fallback[name].response_body
  }

  machines = {
    for name, m in local.machines_raw :
    name => merge(m, {
      # erst lokal, sonst remote; Resultat: Cloud-Init-Inhalt (String)
      userdata = lookup(local.userdata_local, name, lookup(local.userdata_remote, name, ""))
    })
  }
}

