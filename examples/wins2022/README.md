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

**Testen**

Falls das Image nicht Startet, einloggen auf der Graphischen Console von Ubuntu und folgenden Befehl ausführen

    sudo -i
    cd /data/images
    wget http://.... oder scp  # aufbereitete Windows downloaden, kopieren
    wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso # Windows Treiber
    chown virsh:virsh *
    
    sudo virt-install --name=win2022 --ram=4096 --vcpus=2 --import --disk path=WindowsServer2022.qcow2,format=qcow2 \
                 --disk path=virtio-win.iso,device=cdrom --os-variant=win2k22 --graphics vnc,listen=0.0.0.0

Wenn es dann immer noch nicht startet, Image neu erstellen.   
        