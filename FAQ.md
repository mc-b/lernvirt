## 12. FAQ

### Kubeconfig (merge)

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

Perfekt – auf dieser Basis habe ich dir den Text entsprechend angepasst und etwas verfeinert:

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
