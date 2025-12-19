Windows Server 2022
----

Die Windows Images wurden mit Packer erstellt.

Funktionieren mit KVM, QEmu, Proxmoxx etc.

Siehe
* https://github.com/mc-b/terra/tree/main/01-5-packer-windows

Installation

    helm install lab . -n wins2022 --create-namespace -f examples/wins2022/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n wins2022
    
Löschen

    helm uninstall lab -n wins2022 && kubectl delete ns wins2022    
    
Testen

    virtctl vnc vm-0 -n wins2022 

**Einschränkungen**

Braucht entsprechende virt Treiber ansonsten startet Windows nicht.

**Host vorbereiten**
    
    cd /data/images
    sudo apt install -y virt-v2v libguestfs-tools qemu-utils
    sudo systemctl start libvirtd
    export LIBGUESTFS_BACKEND=direct

VirtIO ISO herunterladen

    wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

**Image patchen**

VirtIO-Treiber kopieren    

    sudo mkdir -p /mnt/virtio
    sudo mount virtio-win.iso /mnt/iso
    sudo cp -r /mnt/virtio /mnt/win/virtio
    
    sudo umount /mnt/virtio
    sudo umount /mnt/win
    
Registry-Fix für VirtIO
      
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\viostor]
    "Start"=dword:00000000
    "Group"="SCSI Miniport"
    EOF
    
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet002\Services\viostor]
    "Start"=dword:00000000
    "Group"="SCSI Miniport"
    EOF
    
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\CriticalDeviceDatabase\pci#ven_1af4&dev_1001]
    "Service"="viostor"
    EOF    
        