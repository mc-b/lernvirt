## Automatische Serverinstallation auf Bare-Metal-Hardware

### Variante a) ubuntu-24.04.3-live-server-amd64.iso Image patchen

**ubuntu-24.04.3-live-server-amd64.iso Image downloaden**

z.B. von [Ubuntu Server download](https://ubuntu.com/download/server).

Abstellen, z.B. unter ~/ISO/ubuntu-24.04.3-live-server-amd64.iso

    mkdir -p ~/ISO

**Tools installieren**

    sudo apt install xorrubuntu-24.04.3-live-server-amd64.iso qemu-utils qemu-system-x86 -y

**Arbeitsverzeichnis und ubuntu-24.04.3-live-server-amd64.iso-Inhalt holen**

    rm -rf ~/ws/ubuntu-custom
    mkdir -p ~/ws/ubuntu-custom/{mnt,extract}
    cd ~/ws/ubuntu-custom
    
    sudo mount -o loop ${ubuntu-24.04.3-live-server-amd64.iso} mnt
    rsync -a mnt/ extract/
    sudo umount mnt

**NoCloud-Autoinstall einbauen**

`user-data` und `meta-data` von `control` (Kubevirt Controller) oder `worker` (Worker Node) kopieren

    sudo mkdir -p extract/nocloud
    sudo cp ~/ws/lernvirt/autoinstall/control/* extract/nocloud    

**GRUB-Eintrag anpassen (Autoinstall + serielle Konsole)**

    sudo vi extract/boot/grub/grub.cfg

Im Eintrag z.B. `menuentry 'Try or Install Ubuntu Server' { ... }` die `linux`-Zeile von etwas wie:

    linux   /casper/vmlinuz --- quiet

auf so etwas ändern:

    linux   /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/ console=ttyS0 ---

**Neues Autoinstall-ubuntu-24.04.3-live-server-amd64.iso bauen (Bootstruktur vom Original übernehmen)**

    rm -f ubuntu-24.04.3-live-server-amd64-autoinstall.iso

    xorriso \
      -indev ~/ISO/ubuntu-24.04.3-live-server-amd64.iso \
      -outdev ubuntu-24.04.3-live-server-amd64-autoinstall.iso \
      -map extract/nocloud /nocloud \
      -map extract/boot/grub/grub.cfg /boot/grub/grub.cfg \
      -boot_image any replay

Damit bleibt BIOS/UEFI-Boot wie im Original, nur `grub.cfg` und `nocloud/` werden ersetzt bzw. hinzugefügt.

**Virtuelle Disk anlegen**

    rm -f disk.img
    qemu-img create -f qcow2 disk.img 40G

**VM starten (Autoinstall, seriell im Terminal)**

Variante mit serieller Konsole (empfohlen, da `console=ttyS0` gesetzt ist) und es auch via ssh-Verbindung funktionier:

    qemu-system-x86_64 \
      -machine accel=tcg \
      -m 4096 \
      -cpu qemu64 \
      -cdrom ubuntu-24.04.3-live-server-amd64-autoinstall.iso \
      -boot d \
      -drive file=disk.img,format=qcow2,if=virtio \
      -serial mon:stdio \
      -nographic

Wenn du lieber ein Fenster willst:

    qemu-system-x86_64 \
      -machine accel=tcg \
      -m 4096 \
      -cpu qemu64 \
      -cdrom ubuntu-24.04.3-live-server-amd64-autoinstall..iso \
      -boot d \
      -drive file=disk.img,format=qcow2,if=virtio

**USB Stick schreiben**

    sudo dd if=ubuntu-24.04.3-live-server-amd64-autoinstall.iso of=/dev/sda bs=4M status=progress oflag=sync
    sync
    sudo udisksctl power-off -b /dev/sda

**ACHTUNG**: USB Stick Device `/dev/sda` erst durch `lsblk` ermitteln ansonsten wird der Harddisk überschrieben.

### Variante b) Halbautomatisch

**Ubuntu-Server-Image herunterladen**

Lade das gewünschte Ubuntu-Server-Image herunter und schreibe es auf einen USB-Stick.

**USB-Stick anschliessen**

Stecke den USB-Stick an ein Linux-System an.

**Partition für Cloud-Init erstellen**

Finde den USB Stick

    lsblk

Erstelle auf dem USB-Stick eine neue Partition mit dem Dateisystem **FAT32** und dem Label `cidata`.

    fdisk /dev/sda
       p
       n
       11
       w
       q
      

    sudo apt update
    sudo apt install dosfstools -y
    sudo mkfs.vfat -F 32 /dev/sda11
    sudo mkfs.vfat -F 32 -n cidata /dev/sda11    
    
    sudo mount /dev/sda5 /mnt      

**Cloud-Init-Dateien kopieren**

Kopiere die Dateien `user-data` und `meta-data` auf die neu erstellte Partition.
   
    git clone https://gitub.com/mc-b/lernvirt
    cd lernvirt/autoinstall/control | worker
    cp user-data meta-data /mnt
    sudo umount /mnt