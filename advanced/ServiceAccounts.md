## 🎯 Ziel

* Ein **zentraler ServiceAccount mit Admin-Rechten** für Lehrpersonen
* Zugriff erfolgt über eine **separate `.kube/config`**
* **Zugriff jederzeit entziehbar**, ohne bestehende Admin-Zugänge zu gefährden

  * durch Token-Rotation oder
  * durch Entfernen des RoleBindings

---

## ✅ Vorgehen (sicher & empfohlen)

### 1️⃣ ServiceAccount erstellen

```bash
kubectl create serviceaccount te-access -n kube-system
```

---

### 2️⃣ Admin-Rechte vergeben (ClusterRoleBinding)

```bash
kubectl create clusterrolebinding te-access-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:te-access
```

➡️ Der ServiceAccount hat nun **die gleichen Rechte wie ein Admin-Zertifikat**, ist aber **jederzeit widerrufbar**.

---

### 3️⃣ Token erzeugen (Kubernetes ≥ 1.24)

```bash
kubectl create token te-access -n kube-system
```

🔐 Ausgabe = **JWT Token**
👉 Dieser Token ist **das Zugangspasswort** und muss geschützt behandelt werden.

---

### 4️⃣ API-Server-Adresse ermitteln

```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}{"\n"}'
```

Beispiel:

```
https://192.168.1.100:16443
```

---

### 5️⃣ CA-Zertifikat des Clusters beschaffen (wichtig!)

#### Variante A – aus bestehender kubeconfig

```bash
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > ca.crt
```

#### Variante B – MicroK8s (direkt vom Node)

```bash
sudo cp /var/snap/microk8s/current/certs/ca.crt ./ca.crt
```

➡️ **Ohne CA-Zertifikat ist die Verbindung unsicher.**

---

### 6️⃣ Sichere kubeconfig erstellen

```bash
KUBECONFIG_FILE=te-kubeconfig.yaml
API_SERVER=https://192.168.1.100:16443
TOKEN=<TOKEN_HIER_EINFUEGEN>

kubectl config set-cluster lerncluster \
  --server="$API_SERVER" \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-credentials te-user \
  --token="$TOKEN" \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config set-context te-context \
  --cluster=lerncluster \
  --user=te-user \
  --kubeconfig="$KUBECONFIG_FILE"

kubectl config use-context te-context \
  --kubeconfig="$KUBECONFIG_FILE"
```

✅ Ergebnis:

* TLS wird **korrekt validiert**
* Kein Zertifikat-Bypass
* Nur Token + CA eingebettet

➡️ Diese `te-kubeconfig.yaml` kann **sicher weitergegeben** werden.

---

## 🔍 Aktive Identität prüfen

```bash
kubectl auth whoami
```

Erwartete Ausgabe:

```
system:serviceaccount:kube-system:te-access
```

---

## 🔐 Zugriff sofort entziehen (Notfall / Kursende)

### Variante A – Rechte entfernen (empfohlen)

```bash
kubectl delete clusterrolebinding te-access-admin
```

➡️ Token bleibt gültig, **hat aber keine Rechte mehr**.

---

### Variante B – Zugriff komplett sperren

```bash
kubectl delete serviceaccount te-access -n kube-system
```

➡️ Token **sofort ungültig**.
