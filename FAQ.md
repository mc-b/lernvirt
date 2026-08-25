## 12. FAQ

### Aktive Geräte im Subnetz ermitteln

Der Befehl durchsucht das Subnetz und zeigt alle aktuell erreichbaren Geräte an.

    sudo nmap -sn 10.0.51.0/24
    
### Neuinstallation

> **Wie kann ich eine Neuinstallation der Bare Metal Geräte auslösen**

Lösche auf jedem Gerät die Datei `/boot/lernvirt-installed` und führe einen Reboot aus. 

### Neuinstallation aller Worker erzwingen

> **Wie kann ich eine Neuinstallation der Worker Nodes erzwingen, wenn ich mit ssh nicht mehr darauf komme?**

Nach einer Neuinstallation vom Control kann der SSH-Zugriff vom Control auf die Worker fehlschlagen, weil neue SSH-Keys erzeugt wurden. In diesem Fall müssen alle Worker neu installiert werden.

Auf dem Control in `/srv/tftp/grub/grub.cfg` folgende Zeilen auskommentieren:

    if search --no-floppy --file --set=root /boot/lernvirt-installed; then
        set default="0"
    fi

In `/var/www/html/autoinstall/user-data` vor `late-commands` einfügen:

    shutdown: poweroff
      
    late-commands:
      - curtin in-target --target=/target -- touch /boot/lernvirt-installed

Alle Worker ausschalten und wieder einschalten.

Warten, bis die Worker nach der Neuinstallation selbstständig herunterfahren.

Die auskommentierten Zeilen in `/srv/tftp/grub/grub.cfg` wieder aktivieren.

Worker wieder einschalten.    

### Kubeconfig (merge - besser Context Switch)

> **Wie kann ich mehrere Kubernetes-Cluster in einer einzigen `kubeconfig` bündeln und effizient zwischen Clustern, Contexts und Namespaces wechseln, ohne Konfigurationen manuell anzupassen?**

Mehrere kubeconfigs mergen

    export KUBECONFIG=~/.kube/config:~/.kube/config-lab:~/.kube/config-prod
    kubectl config view --merge --flatten > ~/.kube/config
    chmod 600 ~/.kube/config

Contexts anzeigen & wechseln

    kubectl config get-contexts
    kubectl config use-context <context-name>

Namespaces anzeigen

    kubectl get ns

Namespace temporär nutzen

    kubectl get pods -n alpine

Namespace dauerhaft im Context setzen

    kubectl config set-context --current --namespace=alpine

Best Practice

* **Ein Context = Cluster + Namespace**
* Klare Namen: `alpine`, `m122`
* Kein Arbeiten im `default` Namespace

### Kubeconfig (Context Switch)

> **Wie kann ich effizient zwischen Clustern, Contexts und Namespaces wechseln, ohne Konfigurationen manuell anzupassen?**

Die klassische Variante funktioniert nicht zuverlässig, wenn alle Cluster denselben Benutzernamen verwenden. Deshalb hier eine alternative Lösung per Shell-Script mit Context-Switch.

Zunächst speicherst du pro Cluster die jeweilige `~/.kube/config` lokal unter `.kube/<host>` ab.

Dann erweiterst du deine `.bashrc` (unter Git Bash auf Windows oder auch unter Linux/macOS) wie folgt:

    function cts() {
      case "$1" in
        kvc)
          export KUBECONFIG=~/.kube/kvc
          export HELM_VALUES_HOST="hosts/kvc.yaml"
          export CTX_NAME="kvc"
          ;;
        gx10)
          export KUBECONFIG=~/.kube/gx10
          export HELM_VALUES_HOST="hosts/gx10.yaml"
          export CTX_NAME="gx10"
          ;;
        *)
          echo "❌ Unbekannter Kontext: $1"
          return 1
          ;;
      esac
    
      echo "🔀 Kontext gewechselt → $CTX_NAME"
    }
    
    __update_ps1() {
      local kube=""
      if [[ -n "$CTX_NAME" ]]; then
        kube=" \[\e[35m\][${CTX_NAME}]\[\e[0m\]"
      fi
    
      PS1="\[\e[32m\]\u@\h:\w\[\e[0m\]${kube}\$ "
    }
    
`helm` Aufruf mit Values Datei vom Host
    
    function h() {
      helm "$@" \
        -f "${HELM_VALUES_HOST}"
    }  

---

### Kubernetes Server Zertifikate

> **Wie kann ich weitere Server oder IP für den Kubernetes Cluster zulassen, z.B. für Zugriff via WireGuard?**

**microk8s**

Öffne die Datei:

    sudo vi /var/snap/microk8s/current/certs/csr.conf.template
    
Suche den Abschnitt [ alt_names ]

    [ alt_names ]
    DNS.1 = cloud.tbz.ch
    DNS.2 = mycluster.local
    DNS.3 = api.internal.domain
    DNS.4 = kubeapi.lernvirt.local
    IP.1 = 127.0.0.1
    IP.2 = 10.1.45.8   
    
Zertifikat neu erstellen

    sudo microk8s refresh-certs --cert server.crt  
    
`~/.kube/config` neu erstellen

    microk8s config >~/.kube/config
    
**k3s**

IPs nachtragen

    sudo mkdir -p /etc/rancher/k3s
    hostname -I | awk '{print "tls-san:\n  - "$1"\n  - "$2}' | sudo tee /etc/rancher/k3s/config.yaml

Zertifikate nachführen und Zugriff via `kubectl` freischalten

    sudo systemctl restart k3s   
    sudo chmod +r /etc/rancher/k3s/k3s.yaml     

### Kubernetes max Pods

Per Default sind pro Kubernetes Node in der Regel max. 110 Pods möglich.

Prüfen

    microk8s kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"  pods-capacity="}{.status.capacity.pods}{"\n"}{end}'
    
Um die Anzahl Pods zu erhöhen in der Datei `/var/snap/microk8s/current/args/kubelet` den untenstehenden Eintrag ergänzen

    FILE="/var/snap/microk8s/current/args/kubelet"
    VALUE="250"
    
    if ! grep -qE '^--max-pods=' "$FILE"; then
        echo "--max-pods=$VALUE" | sudo tee -a "$FILE" >/dev/null
        echo "Added --max-pods=$VALUE"
    else
        sudo sed -i -E "s/^--max-pods=.*/--max-pods=$VALUE/" "$FILE"
        echo "Updated --max-pods to $VALUE"
    fi      

`microk8s` neu starten
    
    sudo snap restart microk8s    

---

### 🔀 Port Weiterleitung

> **Wie kann ich einen Port meiner VM (z. B. Port 80) auf meinen lokalen Rechner weiterleiten?**

Der **SSH- (22)** und **HTTPS-Port (443)** jeder VM werden automatisch über einen **Kubernetes LoadBalancer-Service** nach aussen gemappt.

Über den gemappten **SSH-Port** kannst du beliebige weitere Ports aus der VM (z. B. Webserver auf Port 80) per **SSH-Portforwarding** auf deinen lokalen Rechner weiterleiten.

**Gemappten SSH-Port finden**

    kubectl get services -n ap21a

Beispielausgabe:

    NAME                        TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)       
    m169k3s-lernvirt-vm-0       LoadBalancer   10.152.183.75    <pending>     22:32434/TCP   

Hier wurde der **SSH-Port 22 der VM auf NodePort 32434** gemappt.

**Weiterleitung einrichten**

Du kannst jetzt z. B. den **Port 80** der VM (z. B. Webserver) auf deinem lokalen Rechner über Port **8080** zugänglich machen:

    ssh -i ~/.ssh/lerncloud -p 32434 -L 8080:localhost:80 ubuntu@cloud.tbz.ch

Jetzt erreichst du den Webserver der VM ganz einfach im Browser oder per `curl` über:

    http://localhost:8080

### OpenVPN

> **Wie stelle ich unter Linux eine OpenVPN-Verbindung her, wenn mir nur eine `.ovpn`-Konfigurationsdatei vorliegt?**

    sudo openvpn --config myconfig.ovpn
    sudo dhclient tap0
  
Der zweite Befehl holt eine IP-Adresse vom Server und wird nur gebraucht, wenn das nicht automatisch erfolgt.

---

### SSH nur Port Weiterleitung (ohne Shell)

> **Wie kann ich den Lernenden nur Zugriff auf einen bestimmen Port auf meinem System gewähren?**

Das lässt sich mit einem **eingeschränkten SSH-Key** über `authorized_keys` sauber lösen. Der Zugriff wird dabei auf **Port-Forwarding zu einem definierten Ziel/Port** beschränkt, z.B. auf den Ollama-Service.

Beispielannahme:
– Ollama läuft auf `127.0.0.1:11434` (oder einem internen Service)
– Der Benutzer auf dem Zielsystem heisst `ollama`

Zuerst erzeugst du lokal den SSH-Key:

    ssh-keygen -t ed25519 -f ollama-portforward -C "ollama-portforward-only"

Das erzeugt:

* `ollama-portforward` (privat)
* `ollama-portforward.pub` (öffentlich)

Nun trägst du den **öffentlichen Key** auf dem Server in

`/home/ollama/.ssh/authorized_keys` ein – **mit Einschränkungen davor**:

    command="echo 'Port forwarding only'",\
    no-pty,\
    no-agent-forwarding,\
    no-X11-forwarding,\
    permitopen="127.0.0.1:11434" \
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... ollama-portforward-only

Wichtiges dazu, kurz und präzise:

* `permitopen` erlaubt **nur genau diesen Host:Port**
* `no-pty` verhindert eine Shell
* `command=...` ersetzt jede mögliche Kommandoausführung
* Login ist faktisch **nicht interaktiv**
* Der Key ist nur für SSH-Tunneling brauchbar

Verbindung vom Client aus:

    ssh -i ollama-portforward -N -L 11434:127.0.0.1:11434 ollama@server.example.ch

Danach ist Ollama lokal erreichbar unter:

    http://localhost:11434

---

### ReadOnly Zugriff auf Kubernetes Cluster

> **Wie kann ich den Lernenden ReadOnly-Zugriff auf den Kubernetes-Cluster mit Headlamp gewähren?**

Dazu wird ein ServiceAccount mit ReadOnly-RBAC für Headlamp eingerichtet:

    kubectl apply -f https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/addons/headlamp-rbac.yaml
    
Noch als Administrator am besten gleich den Token für den Zugriff auf headlamp erstellen mit einer Gültigkeit von 4 Monaten:

    kubectl -n kube-system create token headlamp-readonly --duration=2880h

Minimale `KUBECONFIG` bzw. Datei `readonly.config` erzeugen:

```bash
HEADLAMP_TOKEN=$(kubectl -n kube-system create token headlamp-readonly)
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
export KUBECONFIG=readonly.config

cat <<EOF >${KUBECONFIG}
apiVersion: v1
kind: Config
clusters:
- name: cluster
  cluster:
    server: ${APISERVER}
    certificate-authority-data: ${CA}
users:
- name: headlamp-readonly
  user:
    token: ${HEADLAMP_TOKEN}
contexts:
- name: headlamp-readonly
  context:
    cluster: cluster
    user: headlamp-readonly
current-context: headlamp-readonly
EOF
```

Zugriff testen:

    kubectl get dv,vmi
    
**Headlamp**

Headlamp, dass neue Dashboard für Kubernetes ist mittels http auf Port 30444 erreichbar.

Mittels dem Token von oben haben die Lernenden Readonly Zugriff auf Headlamp.
    
**ACHTUNG**: dadurch sehen die Lernenden auch die VMs und Default Passwörter der anderen Klassen.    

---

### Podman - Container werden automatisch beendet

> **Warum werden die mit Podman gestarten Container nach einen Logout beendet?**

Damit nicht zu viele Container gleichzeitig ausgeführt werden und den begrenzten Arbeitsspeicher des DGX Spark belegen.

Falls auf ein automatisches Beenden verzichtet werden soll, kann Linger für den entsprechenden Benutzer aktiviert werden.

Beispiel:

    loginctl enable-linger username
    
Dadurch bleibt die systemd-User-Instanz des Benutzers auch ohne aktive Anmeldung bestehen.

---

### DNS Namensauflösung nach reboot VM

> **Warum findet nach einem Reboot des VM Hosts die VMs den Gateway nicht mehr**

Die Datei `/etc/resolv.conf` wird falsch wiederhergestellt der letzte Eintrag fehlt bzw. ist falsch:

    nameserver 127.0.0.53
    options edns0 trust-ad
    search aiaas.svc.cluster.local svc.cluster.local cluster.local

Lösung Namensauflösung mittels Kubernetes wieder aktivieren. Kubernetes Namespace hier `aiaas` beachten.
   
---

### VM kann keine neue IP lösen nach Stromausfall KubeVirt Host

> **Warum kann die VM keine neue IP-Adresse lösen bei einem Reboot/Stromausfall des KubeVirt Hosts**


In `/etc/netplan/50-cloud-init.yaml` steht fix die MAC-Adresse drin. Diese wechselt jedoch noch einem Stromausfall des KubeVirt Hosts.

    network:
      version: 2
      ethernets:
        enp1s0:
          match:
            macaddress: "ee:23:a5:e1:35:e5"

Lösung `/etc/netplan/50-cloud-init.yaml` neu erstellen mit folgendem Inhalt

    sudo rm -f /etc/netplan/50-cloud-init.yaml
    
    sudo tee /etc/netplan/01-enp1s0.yaml >/dev/null <<EOF
    network:
      version: 2
      renderer: networkd
      ethernets:
        enp1s0:
          dhcp4: true
          dhcp6: false
    EOF
    
    sudo netplan generate
    sudo netplan apply
    sudo systemctl enable --now systemd-networkd

**Alternativen**: [kubemacpool](https://github.com/k8snetworkplumbingwg/kubemacpool)

---

### Multi Arch Container Images

> **ARM-basierende Hardware wird immer attraktiver – wie erstelle ich ein Multiarch-Container-Image, das sowohl auf x86_64 als auch auf ARM läuft?**

QEMU & Buildx aktivieren (einmalig)

    docker run --privileged --rm tonistiigi/binfmt --install all
    docker buildx create --use --name multiarch
    docker buildx inspect --bootstrap

Neu builden

    export IMAGE=registry.gitlab.com/ch-mc-b/autoshop-ms/app/shop/order
    export TAG=1.0.0
    
    docker login registry.gitlab.com
    
    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t $IMAGE:$TAG \
      -t $IMAGE:latest \
      --push .

Testen

    docker manifest inspect $IMAGE:$TAG
    
**Auto Shop Container Images**

    cd /tmp
    rm -rf shop
    git clone https://gitlab.com/ch-mc-b/autoshop-ms/app/shop.git
    cd shop
    mv webshop shop

    TARGET=registry.gitlab.com/ch-mc-b/autoshop-ms/app/shop
    
    for tag in 1.0.0 2.0.0 2.0.1 2.0.2 2.0.3 2.1.0 3.0.0 3.1.0 3.2.0 3.3.0 3.4.0
    do
      git checkout -b v$tag origin/v$tag
      for image in catalog customer order shop
      do
        if [ -d "$image" ]; then
          (
            cd "$image"
            docker buildx build . --platform linux/amd64,linux/arm64 --provenance=false --sbom=false -t ${TARGET}/${image}:${tag} --push
          )
        fi
      done
    done
    
**Management**    
    
    rm -rf management
    git clone https://gitlab.com/ch-mc-b/autoshop-ms/app/management.git
    cd management

    TARGET=registry.gitlab.com/ch-mc-b/autoshop-ms/app/management
    
    for tag in 3.2.0
    do
      git checkout -b v$tag origin/v$tag
      for image in sales
      do
        if [ -d "$image" ]; then
          (
            cd "$image"
            docker buildx build . --platform linux/amd64,linux/arm64 --provenance=false --sbom=false -t ${TARGET}/${image}:${tag} --push
          )
        fi
      done
    done    

**Backoffice**    
    
    rm -rf backoffice
    git clone https://gitlab.com/ch-mc-b/autoshop-ms/app/backoffice.git
    cd backoffice

    TARGET=registry.gitlab.com/ch-mc-b/autoshop-ms/app/backoffice
    
    for tag in 3.1.0 4.0.0
    do
      git checkout -b v$tag origin/v$tag
      for image in invoicing shipment
      do
        if [ -d "$image" ]; then
          (
            cd "$image"
            docker buildx build . --platform linux/amd64,linux/arm64 --provenance=false --sbom=false -t ${TARGET}/${image}:${tag} --push
          )
        fi
      done
    done    
    
**IoT**    
    
    rm -rf iot
    git clone https://gitlab.com/ch-mc-b/autoshop-ms/app/iot.git
    cd iot

    TARGET=registry.gitlab.com/ch-mc-b/autoshop-ms/app/iot
    
    for tag in 1.0.0
    do
      for image in alert pipe consumer
      do
        if [ -d "$image" ]; then
          (
            cd "$image"
            docker buildx build . --platform linux/amd64,linux/arm64 --provenance=false --sbom=false -t ${TARGET}/iot-${image}:${tag} --push
          )
        fi
      done
    done 
    
**IIoT**    
    
    rm -rf iiot
    git clone https://gitlab.com/ch-mc-b/autoshop-ms/infra/iiot.git
    cd iiot

    TARGET=registry.gitlab.com/ch-mc-b/autoshop-ms/infra/iiot
    
    for tag in 1.0.0
    do
      for image in mqtt-device-ui mqtt-listener mqtt-operator
      do
        if [ -d "$image" ]; then
          (
            cd "$image"
            docker buildx build . --platform linux/amd64,linux/arm64 --provenance=false --sbom=false -t ${TARGET}/${image}:${tag} --push
          )
        fi
      done
    done         

**Hinweis**: besser gleich via CI/CD Job lösen.
