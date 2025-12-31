## 12. FAQ

### Kubeconfig

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

  

