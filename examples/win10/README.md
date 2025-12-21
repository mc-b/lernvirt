win10
----

Die Windows Images wurden mit Packer erstellt.

Funktionieren mit KVM, QEmu, Proxmoxx etc.

Siehe
* https://github.com/mc-b/terra/tree/main/01-5-packer-windows

Installation

    helm install lab . -n win10 --create-namespace -f examples/win10/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n win10
    
Löschen

    helm uninstall lab -n win10 && kubectl delete ns win10    
    
Testen

    virtctl vnc vm-0 -n win10
    
User und Pasword sind `vagrant`.     
    
**Testen**

Falls das Image nicht Startet, einloggen auf der Graphischen Console von Ubuntu und folgenden Befehl ausführen

    sudo -i
    cd /data/images
    wget http://.... oder scp  # aufbereitete Windows downloaden, kopieren
    wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso # Windows Treiber
    chown virsh:virsh *
    
    virt-install --name=win10 --ram=4096 --vcpus=2 --import --disk path=Windows10.qcow2,format=qcow2 \
                 --disk path=virtio-win.iso,device=cdrom --os-variant=win10  \
                 --graphics vnc,listen=0.0.0.0     

Wenn es dann immer noch nicht startet, Image neu erstellen.