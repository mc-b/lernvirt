## Installation (PXE Autoinstall Ubuntu 24.04)

Das Skript richtet einen **UEFI-fähigen PXE-Server mit ProxyDHCP** ein, um Ubuntu Server 24.04 **vollautomatisch per Netzwerk** zu installieren – ohne bestehenden DHCP-Server zu ersetzen.

**Kernkomponenten:**

* **dnsmasq**
  *ProxyDHCP + TFTP*:
  Erkennt PXE-Clients, liefert Bootloader (`grubx64.efi`) aus und verweist auf Kernel/Initrd.

* **GRUB (UEFI PXE)**
  Stellt ein PXE-Bootmenü bereit und lädt Kernel & Initrd.

* **nginx (HTTP)**
  Liefert:

  * Ubuntu ISO
  * cloud-init `user-data` für Autoinstall

* **Ubuntu Autoinstall (cloud-init)**
  Installation läuft unbeaufsichtigt über `autoinstall` + `cloud-config-url`.

Der bestehende Router bleibt weiterhin **normaler DHCP-Server** (IP, Gateway, DNS).

---

## Architektur / Ablauf

```
[ Client ]
   |
   | DHCPDISCOVER
   v
[ Router ]  -> IP, Gateway, DNS
   |
   | PXE info request
   v
[ dnsmasq ProxyDHCP ] -> grubx64.efi (TFTP)
   |
   v
[ GRUB ] -> vmlinuz + initrd (TFTP)
   |
   v
[ Ubuntu Installer ] -> cloud-init (HTTP)
```

---

## Kurze Schritt-für-Schritt-Anleitung

### 1. Voraussetzungen

* Ubuntu Server (oder VM) im gleichen Netz wie die Clients
* Statische IP für den PXE-Server (z. B. `192.168.1.61`)
* Clients booten im **UEFI PXE-Modus**
* DHCP läuft **bereits auf dem Router**

---

### 2. Script ausführen

    sudo ./pxe-autoinstall.sh

Das Skript erledigt automatisch:

* Installation aller benötigten Pakete
* dnsmasq ProxyDHCP-Konfiguration
* Download der Ubuntu ISO
* Extraktion von `vmlinuz` und `initrd`
* GRUB EFI Setup
* PXE-Bootmenü erstellen
* Starten & Aktivieren von dnsmasq

---

### 3. cloud-init bereitstellen

Lege die Autoinstall-Datei ab unter:

    /var/www/html/autoinstall/user-data

Beispiel:

```yaml
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ubuntu-pxe
    username: ubuntu
    password: "$6$..."
```

(Optional auch `meta-data`, meist leer)

---

### 4. Client booten

* PXE / Network Boot im BIOS aktivieren
* Client starten
* **„Ubuntu Server 24.04 Autoinstall (PXE)“** auswählen
* Installation läuft vollständig automatisch

---

### 5. Logs & Debugging

* PXE / DHCP:

  ```bash
  tail -f /var/log/dnsmasq-pxe.log
  ```
* TFTP-Port prüfen:

  ```bash
  ss -lun | grep :69
  ```
* Autoinstall debug ist bereits aktiv (`debug` Boot-Option)

---

## Ergebnis

✔ Keine Änderung am bestehenden DHCP
✔ UEFI-PXE kompatibel
✔ Vollautomatische Ubuntu Installation
✔ Ideal für Lab-, Lern- & lernvirt-Umgebungen

