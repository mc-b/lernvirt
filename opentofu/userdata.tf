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

# 2) Aufteilen in "lokale Datei vorhanden" vs. "Remote (Modulname)"
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

# 3) HTTP-Fallback für Maschinen, bei denen userdata keine lokale Datei ist

# 3.1 tbz-it/<modul>/refs/heads/master/cloud-init.yaml
data "http" "userdata_master" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/tbz-it/${local.modul}/refs/heads/master/cloud-init.yaml"
}

# 3.2 tbz-it/<modul>/refs/heads/main/cloud-init.yaml
data "http" "userdata_main" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/tbz-it/${local.modul}/refs/heads/main/cloud-init.yaml"
}

# 3.3 generischer Fallback, z.B. lernmaas
data "http" "userdata_fallback" {
  for_each = local.machines_remote

  url = "https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml"
}

# 3.4 Inhalt aus HTTP in lokale Dateien schreiben
resource "local_file" "userdata_remote" {
  for_each = local.machines_remote

  content = try(
    data.http.userdata_master[each.key].response_body,
    data.http.userdata_main[each.key].response_body,
    data.http.userdata_fallback[each.key].response_body,
  )

  filename = "${path.root}/.generated-userdata-${each.key}.yaml"
}

# 4) Finale machines-Struktur, die ans Modul geht (immer Dateipfad)
locals {
  machines_local_final = {
    for name, m in local.machines_local :
    name => merge(m, {
      userdata = "${path.root}/${m.userdata}" # lokale Datei im Projekt
    })
  }

  machines_remote_final = {
    for name, m in local.machines_remote :
    name => merge(m, {
      userdata = local_file.userdata_remote[name].filename
    })
  }

  machines = merge(
    local.machines_local_final,
    local.machines_remote_final,
  )
}
