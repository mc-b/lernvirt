

# 1) Rohdefinition der Maschinen (wie vorher im module-Block)
locals {
  machines_raw = {
    # Podman Umgebung als Test
    dev = {
      hostname = "dev"
      userdata = "cloud-init-test.yaml"
    }

    # VM anhand Terraform Workspace, z.B. "m122"
    vm = {
      hostname = local.modul
      userdata = local.modul # bei Workspace "aws-m122" → "m122"
    }
  }
}

# K8s Cluster
module "vms" {
  source = local.selected_source

  machines = local.machines

  description = "Kubernetes Nodes"
  memory      = 2
  cores       = 2
  storage     = 16

  ports = [22, 80, 443, 16443]

  # MAAS: URL MAAS, Azure: Resource Group, Google: Project-Id
  url = var.url
  # MAAS: API-Key, Azure: Subscription-Id
  key = var.key
  # MAAS: optionales WireGuard VPN
  vpn = var.vpn
}
