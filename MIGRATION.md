Migration von lernmaas auf lernvirt
===================================

[All-in-One](https://github.com/mc-b/lernmaas/tree/master/doc/All-in-one)
----------

Der Server betreibt MAAS (Region- und Rack-Controller) und fungiert gleichzeitig als KVM-Host, über den MAAS virtuelle Maschinen provisionieren kann.

1. MAAS VM sauber stoppen

    virsh shutdown maas

Falls sie nicht reagiert (hartes Ausschalten):

    virsh destroy maas

2. Autostart deaktivieren (damit sie nach Reboot nicht wieder hochkommt) 

    virsh autostart --disable maas

Danach wird die VM beim Neustart des Hosts **nicht mehr automatisch gestartet**.

3. Kontrolle (optional)

    virsh dominfo maas

Bei **Autostart** muss dann `disable` stehen.

MAAS Cluster
------------

Diese Umgebung besteht aus einem Region-/Rack-Server sowie mehreren KVM-Hosts.

Der Region-/Rack-Server übernimmt die Rolle der Kubernetes Control Plane Node, während die KVM-Hosts als Kubernetes Worker Nodes betrieben werden.

Abhängig von den Anforderungen an die Ausfallsicherheit können mehrere Control-Plane-Nodes eingerichtet werden.

**Problematik**: Das Skript `install-lernvirt` (scripts/install-lernvirt.sh) installiert einen Nginx-Webserver, obwohl dieser bereits durch MAAS.io installiert wurde. Dadurch kommt es zu einem Konflikt.

**Lösung**: Stattdessen wird ein Apache-Webserver verwendet. Dieser kann nach der Ausführung von `install-lernvirt.sh` manuell installiert werden:

    sudo apt-get install apache2 -y

Die weiteren Installationsschritte, wie das Einrichten des NFS-Shares, sind mit der MAAS.io-Umgebung kompatibel und haben keinen Einfluss.

**Nach der Installation (siehe unten) von lernvirt auf dem Region-/Rack-Server** werden die KVM-Hosts als Kubernetes Worker Nodes aufbereitet. Die Informationen dazu liefert das MAAS CLI.

    maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | "\(.hostname): \(.ip_addresses | join(", ")) | \(.boot_interface.mac_address // "")"'
        
Maschinen starten, falls Power Off:

    for host in $(maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | .boot_interface.mac_address // empty')
    do
        sudo etherwake -i eno1 ${host}
    done

microk8s Installation: 

    for host in $(maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | .ip_addresses[0]')
    do
        echo ${host}
        ssh ${host} "sudo snap install microk8s --classic"
    done
    
Nachdem microk8s läuft - explizite Angabe des Interfaces (MAAS erstellt auf jeder KVM Host eine Bridge):   
    
    for host in $(maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | .ip_addresses[0]')
    do
        echo ${host}
        ssh ${host} "sudo microk8s kubectl -n kube-system set env daemonset/calico-node IP_AUTODETECTION_METHOD=interface=br-eno1"
    done    

Kontrolle (die Pods müssen gestartet sein):

    for host in $(maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | .ip_addresses[0]')
    do
        echo ${host}
        ssh ${host} sudo microk8s kubectl get pods -A
    done

Worker joinen:
    
    JOIN=$(microk8s add-node --token-ttl 3600 | grep worker | tail -1)
    for host in $(maas $PROFILE machines read | jq -r '.[] | select(.power_type=="manual") | .ip_addresses[0]')
    do
        ssh ${host} "sudo $JOIN"
    done  

Kontrollieren ob alle Nodes zu einem Cluster verbunden sind:

    kubectl get nodes -o wide

Installation lernvirt
---------------------

Installationsschritte wie bei [Autoinstall](autoinstall/nocloud.control/user-data) als `root` ausführen:

    curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/scripts/install-lernvirt.sh | bash -
    curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/microk8s.sh | bash -
    sudo su - ubuntu -c "curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/kubevirt.sh | bash -"
    microk8s kubectl -n kubevirt patch kubevirt kubevirt --type=merge --patch '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":false}}}}'
    
Optional (nur wenn PXE verwendet werden soll):
    
    curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe/install-pxe.sh | bash -     

IP-Adresse des Hosts im Browser anwählen und Anleitung folgen.

Die erstellte [Hosts-Datei](hosts/README.md) beinhaltet die lokalen IP-Adressen. Diese sind vor Verwendung des Rechners anzupassen auf die WireGuard/externen IP Adressen umzustellen.
