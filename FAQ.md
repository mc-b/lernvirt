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
    
    PROMPT_COMMAND="__update_ps1"

### Änderungen im Überblick:

* **Verbesserte Lesbarkeit**: Klarere Struktur und Formulierungen im erklärenden Text.
* **Statt `__short_pwd`**: Jetzt wird `\w` verwendet, was im Prompt den vollständigen Pfad (`$PWD`) anzeigt.
* **Prompt-Anzeige**: Zeigt zusätzlich den aktiven Kubernetes-Context in lila `[CTX_NAME]`.
* **Unicode-Icons**: Kleine Icons zur besseren Lesbarkeit bei Kontextwechsel und Fehlermeldungen.

---

Wenn du möchtest, kann ich dir auch eine Zsh-kompatible Version oder Unterstützung für Autovervollständigung des `cts`-Befehls geben.


Zuerst sind pro Cluster die `~/.kube/config` Dateien lokal als `.kube/<host>` zu speichern.

Anschliessend `.bashrc` (Git/Bash auf Windows) wie folgt erweitern:

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
          echo "Unknown context: $1"
          return 1
          ;;
      esac
    
      echo "🔀 Switched context → $CTX_NAME"
    }
    __update_ps1() {
      local kube=""
      if [[ -n "$CTX_NAME" ]]; then
        kube=" \[\e[35m\][$(basename "$CTX_NAME")]\[\e[0m\]"
      fi
    
      PS1="\[\e[32m\]\u@\h:\w\[\e[0m\]${kube}\$ "
    }
    
    PROMPT_COMMAND="__update_ps1"
    

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

  

