# Beispiel für Lernumgebungen basierend auf DevContainern

Ein DevContainer ist eine **vordefinierte Entwicklungsumgebung in einem Container**. Er legt fest, welches Betriebssystem, welche Tools, welche Versionen und welche Einstellungen verwendet werden. Öffnet man ein Projekt in VS Code, wird genau diese Umgebung automatisch gestartet.

Für die Lernumgebung bedeutet das:

Alle arbeiten **mit exakt derselben Umgebung**. Es spielt keine Rolle, ob jemand Windows, macOS oder Linux nutzt. Es muss lokal praktisch nichts installiert oder konfiguriert werden. Typische Probleme wie „bei mir läuft es nicht“ entfallen.

Technisch wird das über eine `.devcontainer/devcontainer.json` gesteuert. Darin ist definiert:

* welches Container-Image verwendet wird,
* welche Tools installiert sind (z. B. Docker, Python, Terraform),
* welche Ports, Volumes und User-Rechte gelten.

## Beispiele 

In VSCode "Open Folder" und lernvirt/examples/[Beispiel] öffnen. Rechts unten erscheint ReOpen in DevContainer.

- **alpine** - Automatisieren mit Scripts - [Alpine Umgebung verwenden (Bash Umgebung)](../alpine)
- **aiaas** - [AI Umgebung (OpenAI, RAG, MCP Jupyter Kernel)](../aiaas)
- **duk** - [Docker und Kubernetes](../duk)

Siehe auch vorhandene `README.md` in den Unterverzeichnissen `.devcontainer`.

## Installation

[Docker Desktop](https://www.docker.com/products/docker-desktop/) installieren oder WSL Umgebung einrichten. Auf Linux und MAC genügt die Installation von docker.

**WSL** (nur Windows)

**Standard Variante** ohne `cloud-init`.

    wsl --install --no-launch -d Ubuntu-24.04
    wsl # z.B. User ubuntu
    exit
    
    wsl 
    sudo apt-get update
    sudo apt-get install -y openssh-server docker.io docker-compose
    sudo usermod -aG docker ubuntu 
    
    # ssh-key vom lokalen Rechner in WSL Umgebung übertragen
    # testen vom Windows Rechner
    ssh ubuntu@localhost docker ps

**Eigene Installation** mit `cloud-init`

Erzeugen eines leeren Distribution 

    wsl --install --no-launch -d Ubuntu-24.04
    wsl --terminate Ubuntu-24.04
    wsl --export Ubuntu-24.04 D:/WSL/ubuntu/ubuntu24.04.tar
    wsl --unregister Ubuntu-24.04
    
**Cloud-init** vorbereiten

WSL unterstützt [Cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/datasources/wsl.html).

Dazu ist im Windows ein Verzeichnis `C:\Users\<User-ID>\.cloud-init` anzulegen und die Datei `docker.user-data` dorthin zu kopieren.

    mkdir -p ~/.cloud-init
    cp docker.user-data ~/.cloud-init/
    wsl --import docker D:/WSL/docker D:/WSL/ubuntu/ubuntu24.04.tar --version 2 

    wsl --setdefault docker
    wsl cloud-init status --wait
    wsl --terminate docker
    wsl
    
Bei Fehlern docker Umgebung weglöschen und von vorne anfangen

    wsl --unregister docker     
    
In **VSCode** - Settings -> DevContainer

* Aktivieren: Execute in WSL
* Execute in WSL Distro: `Ubuntu-24.04` oder `docker` eintragen.
* Aktivieren: Forward WSL-Services

### Links

* [Einführung in Entwicklungscontainer](https://docs.github.com/de/codespaces/setting-up-your-project-for-codespaces/adding-a-dev-container-configuration/introduction-to-dev-containers)
