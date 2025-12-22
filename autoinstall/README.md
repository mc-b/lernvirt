## Automatische Serverinstallation auf Bare-Metal-Hardware

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
       t
       11
       w
       q
      

    sudo apt update
    sudo apt install dosfstools -y
    sudo mkfs.vfat -F 32 /dev/sda5
    sudo mkfs.vfat -F 32 -n cidata /dev/sda5    
    
    sudo mount /dev/sda5 /mnt      

**Cloud-Init-Dateien kopieren**

Kopiere die Dateien `user-data` und `meta-data` auf die neu erstellte Partition.
   
    git clone https://gitub.com/mc-b/lernvirt
    cd lernvirt/autoinstall/control | worker
    cp user-data meta-data /mnt
    sudo umount /mnt
