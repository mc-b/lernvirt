# OpenShift SNO fuer lernvirt pxe-stack — v5

Der PXE-Server stellt nur gemeinsame RHCOS-Images, `openshift-install` und Scripts bereit. Clustername und Zielsystem kommen weiterhin aus `rack.conf`.

## Installation auf dem PXE-Server

```bash
sudo ./install-openshift-sno.sh
```

Beispiel `rack.conf`:

```bash
"80:ee:73:ef:0d:e9|openshift-sno|terra5"
```

Danach PXE-Boot des Zielsystems. Kein Prepare-/Finish-Schritt auf dem PXE-Server.

## v5: Korrekturen gegenueber v4

- Der v4-Hook `lernvirt-patch-master-ign.service` wurde komplett entfernt.
- Es gibt keine eigene Abhaengigkeit mehr zu `bootkube.service` oder `install-to-disk.service`.
- Persistente Dateien werden ausschliesslich als Day-1 `MachineConfig` unter `openshift/` eingebracht.
- Die Bootstrap-in-Place-Ignition wird nur noch um Hostname, `/etc/hosts`, `cluster.env`, Profil und eine reine Console-Ausgabe fuer `bootkube.service` erweitert.
- `/usr/local/bin/oc` und `/bin/oc` werden nicht veraendert.
- Root verwendet nach Moeglichkeit `/etc/kubernetes/kubeconfig`; waehrend Bootstrap gibt es einen Fallback auf `/etc/kubernetes/bootstrap-secrets/kubeconfig`.
- `/etc/hosts`, `/etc/hostname`, `cluster.env` und das Profil erhalten jetzt garantiert ein abschliessendes Newline.

Persistiert werden:

```text
/etc/hostname
/etc/hosts
/var/lib/lernvirt/cluster.env
/etc/profile.d/lernvirt-openshift.sh
```

Die generierten Installer-Credentials werden nicht mehr durch eigene BIP-Hooks in die finale Ignition geschrieben. Dadurch bleibt der OpenShift-Bootstrap selbst unangetastet.

## Zielablauf

```text
PXE RHCOS Live
 -> Clustername aus rack.conf
 -> IP/Gateway/DNS/MAC erkennen
 -> install-config.yaml
 -> openshift-install create manifests
 -> Day-1 MachineConfig fuer Hostname/Hosts
 -> openshift-install create single-node-ignition-config
 -> Live-Ignition nur um lokale Hostdaten erweitern
 -> kexec in cluster-spezifische RHCOS-Live-Phase
 -> nativer OpenShift Bootstrap-in-Place
 -> Installation auf INSTALL_DISK
 -> Reboot
 -> nativer Post-Reboot-Bootstrap
```

`nginx` auf dem PXE-Server wird nicht veraendert.
