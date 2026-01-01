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