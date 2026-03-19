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

    sudo ./lerncloud-setup.sh --dry-run
    
Alles ausführen

    sudo ./lerncloud-setup.sh    


    