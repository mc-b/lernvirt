Hilfsscripte
------------

## ServiceAccount & kubeconfig Script

Dieses Script erstellt für eine Lehrperson einen **dedizierten Kubernetes ServiceAccount** mit **Cluster-Admin-Rechten** und erzeugt daraus eine **eigene kubeconfig-Datei**.

Die kubeconfig kann unabhängig von der globalen `.kube/config` verteilt und bei Bedarf einfach entzogen werden.

**Zweck**

- Kein Weitergeben der persönlichen `.kube/config`
- Schneller Entzug von Zugriffsrechten
- Eine kubeconfig pro Lehrperson (Kürzel)

**Verwendung**

    ./script/create-kubeconfig.sh <KUERZEL>

Beispiel:

    ./script/create-kubeconfig.sh ALP

**Ergebnis**

- ServiceAccount: `te-alp` (Namespace: `kube-system`)
- ClusterRoleBinding: `cluster-admin`
- kubeconfig Datei: `ALP-kubeconfig.yaml`

**Test**

    KUBECONFIG=ALP-kubeconfig.yaml kubectl auth whoami

## Build-Script (`build.sh`)

Das Build-Script erzeugt aus dem generischen Helm-Chart **lernvirt** eine **environment-spezifische, vollständig aufgelöste Chart-Variante**.

Der Build erfolgt **ohne Helm-Overrides** und ohne Template-Logik in `values.yaml`.

**Zweck**

- Trennung von Basis- und Environment-Konfiguration
- Eindeutige Chart-Namen pro Environment
- Reproduzierbare Helm-Pakete

**Verwendung**

    ./script/build.sh <environment>

Der Parameter <environment> muss einem Dateinamen unter env/ entsprechen:

    ./script/build.sh lernmaas 
    
## rpodman Umgebung

`rpodman` ist ein dedizierter, eingeschränkter System-User für den Betrieb von rootless Podman-Containern. Ziel ist eine kontrollierte Container-Sandbox ohne Root-Rechte, ohne Host-Dateisystem-Mounts und mit klar definierter Befehlsschnittstelle.

Setup (z.B. als User `ubuntu`)

    git clone https://github.com/mc-b/lernvirt
    sudo bash lernvirt/scripts/setup-rpodman.sh

Architektur

* Eigener Linux-User (`rpodman`)
* Rootless Podman (keine Root-Daemon-Instanz)
* Restricted Bash als Login-Shell
* Fixierter PATH mit Whitelist von erlaubten Binaries
* Optionaler Podman-Wrapper zur Verhinderung von Host-Bind-Mounts
* Eigene containers.conf (z.B. cgroupfs, userns=auto)
* SSH-Zugang mit dediziertem Public Key

Sicherheitsmodell

* Container laufen im User-Namespace des Users.
* Kein Zugriff auf Root-Rechte.
* Kein Zugriff auf Systempfade ausserhalb der normalen User-Rechte.
* Host-Bind-Mounts können unterbunden werden.
* Nur definierte Kommandos stehen zur Verfügung.
* Umgebung ist klar vom restlichen System getrennt.

Das Remove-Script (`sudo lernvirt/scripts/remove-podman.sh`) entfernt vollständig:

* User `rpodman`
* dessen Home-Verzeichnis
* rootless Container, Images, Volumes
* Konfigurations- und Runtime-Daten

Systemweite (rootful) Podman-Instanzen bleiben unangetastet.

## lerncloud Scripts

Nach einer minimalen Installation können die lerncloud Scripte ausgeführt werden.

Anzeigen was ausgeführt wird

    sudo bash ./lerncloud-setup.sh --dry-run
    
Alles ausführen

    sudo bash ./lerncloud-setup.sh    


## Live System

**Builden**

    git pull
    sudo PROFILE=headless bash ./scripts/build-live-lernvirt.sh

    git pull
    sudo PROFILE=gui bash ./scripts/build-live-lernvirt.sh

**Starten**

    export PROFILE=headless 
    sudo chmod 666 /dev/kvm        
    cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/OVMF_VARS_4M-${PROFILE}.fd
    qemu-system-x86_64  -m 8192 -enable-kvm -cpu host \
                        -drive file="build-${PROFILE}/ubuntu-${PROFILE}-live-noble-amd64.iso",media=cdrom,format=raw \
                        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
                        -drive if=pflash,format=raw,file=/tmp/OVMF_VARS_4M-${PROFILE}.fd \
                        -nographic -serial mon:stdio

    export PROFILE=gui 
    sudo chmod 666 /dev/kvm    
    cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/OVMF_VARS_4M-${PROFILE}.fd
    qemu-system-x86_64  -m 8192 -enable-kvm -cpu host \
                        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
                        -drive if=pflash,format=raw,file=/tmp/OVMF_VARS_4M-${PROFILE}.fd \
                        -drive file="build-${PROFILE}/ubuntu-${PROFILE}-live-noble-amd64.iso",media=cdrom,format=raw
    
**Boot Disk erstellen**
    
    sudo dd if=build-${PROFILE}/ubuntu-${PROFILE}-live-noble-amd64.iso of=/dev/sda bs=4M status=progress oflag=sync
    sync
    sudo udisksctl power-off -b /dev/sda    

**Im Live System**

Kubernetes in PodMan `kind` starten

    kind create cluster --config kind-config.yaml --name kind --retain
    
Dashboard aktivieren

    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/data/DataVolume.yaml
    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/addons/dashboard.yaml
    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/addons/dashboard-admin.yaml  
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'

K3s Kubernetes starten 

    mkdir -p /tmp/k3sdata/k3s
    curl -sfL https://get.k3s.io | \
      INSTALL_K3S_EXEC='server --cluster-init --disable traefik --disable servicelb --data-dir /tmp/k3sdata/k3s' sh -

**Debugging**

Allgemeiner Schnellcheck nach dem Boot
    
    systemctl --failed
    systemctl status gdm3 NetworkManager systemd-resolved ssh lerncloud-firstboot --no-pager
    journalctl -b -p err..alert --no-pager
    dmesg -T | tail -20
    
GUI gezielt debuggen

    systemctl status gdm3 --no-pager -l
    journalctl -b -u gdm3 --no-pager
    journalctl -b | grep -Ei 'gdm|gnome-shell|mutter|Xorg|wayland|drm|gpu|mesa'    
    