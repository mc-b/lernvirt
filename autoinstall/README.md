## Serverinstallation auf Bare-Metal-Hardware

**ubuntu-...iso Image downloaden**

z.B. von [Ubuntu Server download](https://ubuntu.com/download/server).

Abstellen, z.B. unter ~/ISO/ubuntu-24.04.4-live-server-amd64.iso

    mkdir -p ~/ISO
    cd ~/ISO
    wget https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso
    
**Repository clonen**

    git clone https://github.com/mc-b/lernvirt
    cd lernvirt/autoinstall    

**Tools installieren**

    sudo apt install -y xorriso
    
**Optional: Weitere Installationsumgebungen hinzufügen**

Passende Umgebung `nocloud.*` aussuchen und Verzeichnis kopieren, z.B. auf `nocloud.myenv`

    cp -rp nocloud.control nocloud.myenv

`user-data` und `meta-data` Anpassen.

Grub Menu anpassen, bzw. erweitern

    vi boot/grub/grub.cfg

`xorriso` Befehl um eigene Umgebung erweitern

    xorriso \
      -indev ~/ISO/ubuntu-24.04.4-live-server-amd64.iso \
      -outdev ubuntu-autoinstall.iso \
      ...
      -map nocloud.gui /nocloud.myenv \
      ...

**Neues Autoinstall Ubuntu bauen**

    cd lernvirt/autoinstall
    rm -f ubuntu-autoinstall.iso
    
    xorriso \
      -indev ~/ISO/ubuntu-24.04.4-live-server-amd64.iso \
      -outdev ubuntu-autoinstall.iso \
      -map nocloud.control /nocloud.control \
      -map nocloud.min /nocloud.min \
      -map nocloud.gui /nocloud.gui \
      -map nocloud.k8sws /nocloud.k8sws \
      -map nocloud.worker /nocloud.worker \
      -map nocloud.maas /nocloud.maas \
      -map nocloud.k3sws /nocloud.k3sws \
      -map boot/grub/grub.cfg /boot/grub/grub.cfg \
      -boot_image any replay

Damit bleibt BIOS/UEFI-Boot wie im Original, nur `grub.cfg` und `nocloud/` werden ersetzt bzw. hinzugefügt.

**USB Stick schreiben**

    sudo dd if=ubuntu-autoinstall.iso of=/dev/sda bs=4M status=progress oflag=sync
    sync
    sudo udisksctl power-off -b /dev/sda

**ACHTUNG**: USB Stick Device `/dev/sda` erst durch `lsblk` ermitteln im schlimmsten Fall wird der Harddisk überschrieben.


### Boot Ablauf

```
[ GRUB ] -> vmlinuz + initrd (TFTP)
   |
   v
[/boot/lernvirt-installed] -> vorhanden -> lokal Boot || Neuinstallation
   |
   v
[ Ubuntu Installer ] -> cloud-init (HTTP) -- touch /boot/lernvirt-installed
```
