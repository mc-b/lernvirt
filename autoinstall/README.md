## Automatische Serverinstallation auf Bare-Metal-Hardware

### ubuntu-....iso Image patchen

**ubuntu-...iso Image downloaden**

z.B. von [Ubuntu Server download](https://ubuntu.com/download/server).

Abstellen, z.B. unter ~/ISO/ubuntu-24.04.3-live-server-amd64.iso

    mkdir -p ~/ISO

**Tools installieren**

    sudo apt install xorrubuntu-24.04.3-live-server-amd64.iso qemu-utils qemu-system-x86 -y
    
**Optional: Arbeitsverzeichnis und ubuntu-24.04.3-live-server-amd64.iso-Inhalt holen **

    rm -rf ~/ws/ubuntu-custom
    mkdir -p ~/ws/ubuntu-custom/{mnt,extract}
    cd ~/ws/ubuntu-custom
    
    sudo mount -o loop ${ubuntu-24.04.3-live-server-amd64.iso} mnt
    rsync -a mnt/ extract/
    sudo umount mnt

**Optional: NoCloud-Autoinstall einbauen**

`user-data` und `meta-data` von `control` (Kubevirt Controller) oder `worker` (Worker Node) kopieren

    sudo mkdir -p extract/nocloud
    sudo cp ~/ws/lernvirt/autoinstall/control/* extract/nocloud    

**Optional: GRUB-Eintrag anpassen für Autoinstall**

    sudo vi extract/boot/grub/grub.cfg

Im Eintrag z.B. `menuentry 'Try or Install Ubuntu Server' { ... }` die `linux`-Zeile von etwas wie:

    linux   /casper/vmlinuz --- quiet

auf so etwas ändern:

    linux   /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/nocloud/ ---

**Neues Autoinstall-ubuntu-24.04.3-live-server-amd64.iso bauen (Bootstruktur vom Original übernehmen)**

    rm -f ubuntu-autoinstall.iso
    
    xorriso \
      -indev ~/ISO/ubuntu-24.04.3-live-server-amd64.iso \
      -outdev ubuntu-autoinstall.iso \
      -map nocloud.control /nocloud.control \
      -map nocloud.min /nocloud.min \
      -map nocloud.gui /nocloud.gui \
      -map nocloud.worker /nocloud.worker \
      -map nocloud.maas /nocloud.maas \
      -map boot/grub/grub.cfg /boot/grub/grub.cfg \
      -boot_image any replay

Damit bleibt BIOS/UEFI-Boot wie im Original, nur `grub.cfg` und `nocloud/` werden ersetzt bzw. hinzugefügt.

**Optional: Virtuelle Disk anlegen**

    rm -f disk.img
    qemu-img create -f qcow2 disk.img 40G

**Optional: VM starten (Autoinstall, seriell im Terminal)**

Im aktuellen Terminalfenster (funktoniert auch in ssh-Verbindung) starten:

    qemu-system-x86_64 \
      -machine accel=tcg \
      -m 4096 \
      -cpu qemu64 \
      -cdrom ubuntu-autoinstall.iso \
      -boot d \
      -drive file=disk.img,format=qcow2,if=virtio \
      -serial mon:stdio \
      -nographic

Als separates Fenster (besser zum stoppen):

    qemu-system-x86_64 \
      -machine accel=tcg \
      -m 4096 \
      -cpu qemu64 \
      -cdrom ubuntu-autoinstall.iso \
      -boot d \
      -drive file=disk.img,format=qcow2,if=virtio

**USB Stick schreiben**

    sudo dd if=ubuntu-autoinstall.iso of=/dev/sda bs=4M status=progress oflag=sync
    sync
    sudo udisksctl power-off -b /dev/sda

**ACHTUNG**: USB Stick Device `/dev/sda` erst durch `lsblk` ermitteln ansonsten wird der Harddisk überschrieben.
