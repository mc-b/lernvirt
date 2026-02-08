# daas - Docker und Kubernetes as a Service

Stellt zwei Dev Container zu Verfügung.
* dd - Docker Desktop, d.h. docker CLI ist installiert es wird aber auf die Docker Desktop Umgebung zugegriffen
* dind - Docker in Docker, d.h. es läuft eine interne Docker Umgebung im Dev Container

### Kubernetes Cluster (kind) erstellen

In der `dd` Variante kann ausserhalb des Dev Containers ein Kubernetes Cluster erstellt werden, welcher nochher innerhalb des Dev Containers angesprochen werden kann.

    kind create cluster --config kind-config.yaml --name kind --retain
    
Feintuning:
* `~/.kube/config` - Ausserhalb des Dev Containers server: https: auf `https://127.0.0.1:6443 ändern. Und Datei in Dev Container kopieren.
* Innerhalb des Dev Containers IP-Adresse des Docker Netzwerkes verwenden. Zuerst `kubectl --kubeconfig config get pods` ausführen, dann erscheint in der Fehlermeldung die IP des K8s Clusters.
    
**Dashboard und PersistentVolume**

    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/data/DataVolume.yaml
    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/addons/dashboard.yaml
    kubectl apply -f https://raw.githubusercontent.com/mc-b/lerncloud/master/addons/dashboard-admin.yaml 

**Metrics Server**

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml && \
    kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'

**Ingress**

    kubectl label node kind-control-plane ingress-ready=true kubernetes.io/os=linux 
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/kind/deploy.yaml
    
**Keep-Alive**
    
    docker ps --filter "name=kind" --format "{{.Names}}" | xargs -n1 docker update --restart unless-stopped    
