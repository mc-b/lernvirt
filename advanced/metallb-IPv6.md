## MetalLB – Allgemeine Anleitung (nicht getestet!)

![Image](https://miro.medium.com/v2/resize%3Afit%3A1400/0%2ATcd6i2MpOw05bEi0.png)

![Image](https://www.redhat.com/rhdc/managed-files/ohc/mauro%20-%20MetalLB%20in%20BGP%20Mode-1.png)

![Image](https://miro.medium.com/v2/resize%3Afit%3A1400/0%2Ay5Dp7dUJeezXPUxG.png)

![Image](https://www.densify.com/wp-content/uploads/article-k8s-capacity-kubernetes-service-overview.svg)

### Was ist MetalLB?

**MetalLB** ist ein Load-Balancer für **bare-metal Kubernetes-Cluster**.
Er stellt Kubernetes-Services vom Typ `LoadBalancer` bereit, **ohne Cloud-Provider**.

MetalLB vergibt **öffentliche oder private IPv4/IPv6-Adressen** aus einem definierten Adressbereich.

---

## Grundprinzip

1. Du besitzt oder erhältst ein **IP-Präfix** von einem **Provider**
   (z. B. IPv6 /48 oder /56)
2. Ein **Teil dieses Präfixes** wird MetalLB zur Verfügung gestellt
3. MetalLB weist Services automatisch IP-Adressen zu
4. Der Datenverkehr wird zu den richtigen Kubernetes-Pods geleitet

---

## Voraussetzungen

### Netzwerk

* Ein geroutetes **IPv4- und/oder IPv6-Netz**
* Das Präfix ist **bis zu deinem Router** geroutet
* Firewall erlaubt explizit gewünschten Traffic

### Kubernetes

* Kubernetes ≥ 1.23 (empfohlen aktueller)
* CNI mit IPv6-Support (z. B. Cilium, Calico)
* MetalLB ≥ v0.13

---

## Betriebsarten von MetalLB

### 🔹 Variante A: Layer-2-Modus (einfach)

**Funktionsweise**

* MetalLB beantwortet ARP (IPv4) bzw. NDP (IPv6)
* Eine Node übernimmt die IP („Leader“)

**Eigenschaften**

* Sehr einfach
* Kein Routing-Protokoll nötig
* Geeignet für:

  * Lab
  * Schulnetze
  * Kleine On-Prem-Umgebungen

**Einschränkungen**

* Nur innerhalb eines Layer-2-Netzes
* Failover dauert Sekunden

---

### 🔹 Variante B: BGP-Modus (empfohlen für produktiv)

**Funktionsweise**

* MetalLB spricht **BGP** mit einem Router
* IP-Netze werden dynamisch angekündigt

**Eigenschaften**

* Hochverfügbar
* Schnellstes Failover
* Skalierbar
* Industriestandard

**Geeignet für**

* Rechenzentren
* Campus-Netze
* Professionelle Kubernetes-Setups

---

## Beispiel: IPv6-Adresspool definieren

> Du nimmst **einen /64-Block** aus deinem Provider-Präfix.

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ipv6-pool
  namespace: metallb-system
spec:
  addresses:
  - 2001:db8:abcd:100::/64
```

---

## Advertisement konfigurieren

### Layer-2

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-adv
  namespace: metallb-system
```

---

### BGP

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-adv
  namespace: metallb-system
```

Zusätzlich wird ein **BGPPeer** definiert:

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPPeer
metadata:
  name: router
  namespace: metallb-system
spec:
  peerAddress: 2001:db8::1
  peerASN: 65001
  myASN: 65010
```

---

## Service mit IPv6 veröffentlichen

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: LoadBalancer
  ipFamilies:
    - IPv6
  ipFamilyPolicy: SingleStack
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: web
```

➡️ MetalLB weist automatisch eine Adresse aus dem Pool zu.

---

## Sicherheit (sehr wichtig)

* IPv6 **hat kein NAT**
* Jeder Service ist direkt erreichbar
* Firewall & NetworkPolicies sind Pflicht
* Empfehlung:

  * Default-Deny
  * Nur benötigte Ports öffnen

---

## Best Practices

✔ /64 pro Pool
✔ BGP für produktive Umgebungen
✔ Trennung:

* Nodes
* Services
* Management
  ✔ Monitoring (BGP-Sessions, IP-Pools)

---

## Typische Architektur

```
[ Internet / Provider ]
          |
       [ Router ]
          |
     (BGP oder L2)
          |
   [ MetalLB ]
          |
  [ Kubernetes Services ]
```

---

## Fazit

**MetalLB macht Kubernetes cloud-unabhängig.**
Mit einem Provider-gerouteten IP-Präfix kannst du:

* echte öffentliche IPs nutzen
* IPv6 vollständig einsetzen
* LoadBalancer wie in der Cloud betreiben

