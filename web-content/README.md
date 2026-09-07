## Web-Content über Traefik

Nginx wurde bisher verwendet, um Dateien aus `/var/www/html` über Port `80` bereitzustellen. Da Traefik als Ingress-Controller ebenfalls Port `80` und `443` verwendet, überschneiden sich beide Dienste.

Traefik übernimmt deshalb den externen HTTP-Zugriff. Die Dateien werden intern durch einen kleinen `web-content`-Pod ausgeliefert.

### Nginx deaktivieren

    sudo systemctl disable --now nginx

### Web-Content aktivieren

Namespace erstellen und Netzwerk und Workload installieren:

    kubectl create ns web-content
    kubectl apply -n web-content -f https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/web-content/network.yaml
    kubectl apply -n web-content -f https://raw.githubusercontent.com/mc-b/lernvirt/refs/heads/main/web-content/workload.yaml

Damit werden unter anderem folgende Inhalte bereitgestellt:

```text
/
├── alpine/
├── autoinstall/
└── linux/
```

Der eigentliche externe Zugriff wird anschliessend über einen separaten Ingress eingerichtet. Dabei gibt es zwei Varianten.

### Variante A: HTTP ohne Let's Encrypt

Für einen einfachen Zugriff über HTTP genügt ein Ingress ohne TLS-Konfiguration:

```bash
kubectl apply -n web-content -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-content
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-content
                port:
                  number: 80
EOF
```

Der Zugriff erfolgt anschliessend direkt über die IP-Adresse bzw. einen vorhandenen DNS-Namen:

```text
http://<IP>/
```

### Variante B: HTTPS mit Let's Encrypt

Für einen öffentlichen DNS-Namen kann Traefik zusammen mit cert-manager automatisch ein Let's-Encrypt-Zertifikat beziehen.

Zuerst wird einmalig ein `ClusterIssuer` erstellt:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@mydns
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
EOF
```

Anschliessend wird der Ingress für `web-content` mit TLS eingerichtet:

```bash
kubectl apply -n web-content -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-content
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - cloud.mydns
      secretName: cloud-mydns-tls
  rules:
    - host: cloud.mydns
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-content
                port:
                  number: 80
EOF
```

Danach ist der Web-Content über HTTPS erreichbar:

* https://cloud.mydns/


