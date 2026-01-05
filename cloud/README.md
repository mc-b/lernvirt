## Erstellen einer Modulumgebung für eine Klasse (Cloud, opentofu)

Zuerst ist [opentofu](https://opentofu.org/) (fork von [terraform](https://developer.hashicorp.com/terraform)) zu installieren.

## 1. Workspace wählen

Workspace-Name: `<provider>-<modul>`

Beispiele:

* `multipass-m122`
* `aws-m122`
* `maas-m346`

Dabei gilt:

* `<provider>` bestimmt das Terraform-Modul (`multipass`, `aws`, `azure`, `gcp`, `maas`, `lernmaas` …).
* `<modul>` (z.B. `m122`) wird für `userdata` als Kurs-/Modulname verwendet.

**Ablauf**

1. Geeigneten Workspace wählen, z.B.:

    tofu workspace select aws-m122

2. `tofu init`, `tofu plan`, `tofu apply` ausführen.

## 2. VMs definieren

Die VMs werden im Root in `main.tf` im Block `locals.machines_raw` definiert, z.B.:

    locals {
      machines_raw = {
        dev = {
          hostname = "dev"
          userdata = "cloud-init-development.yaml"  # lokale Datei
        }
    
        build = {
          hostname = "build"
          userdata = local.modul                     # Modul aus Workspace, z.B. "m122"
        }
      }
    }

Es gibt zwei Verwendungsarten für `userdata`:

1. **Lokale Cloud-Init-Datei**

   * `userdata = "cloud-init-xyz.yaml"`
   * Datei liegt im Root-Verzeichnis.
   * Wird direkt als Template verwendet.

2. **Modul aus Workspace**

   * `userdata = local.modul` (Suffix aus Workspace, z.B. `m122`).

   * Es wird eine Fallback-Kette von URLs probiert:

     1. `https://raw.githubusercontent.com/tbz-it/<modul>/refs/heads/master/cloud-init.yaml`
     2. `https://raw.githubusercontent.com/tbz-it/<modul>/refs/heads/main/cloud-init.yaml`
     3. `https://raw.githubusercontent.com/mc-b/lernmaas/master/gns3/cloud-init.yaml`

   * Die gefundene Cloud-Init wird in als `userdata`-Template verwendet.


