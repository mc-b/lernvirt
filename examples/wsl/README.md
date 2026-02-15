Windows Subsystem Linux (WSL)
=============================

Windows Subsystem for Linux (WSL) ist eine Funktion von Windows, mit der sich eine vollständige Linux-Umgebung direkt unter Windows ausführen lässt – ohne klassische virtuelle Maschine oder Dual-Boot-Setup. 

Dazu empfiehlt es sich, zuerst das [Windows Terminal](https://learn.microsoft.com/en-us/windows/terminal/install) zu installieren, da es eine moderne Oberfläche für mehrere Shells und Distributionen bietet.

Danach können bei Bedarf weitere Distributionen installiert werden, etwa Alpine Linux, RedHat, SuSe oder Ubuntu.

**Installation WSL und wichtige Befehle**

    wsl --install
    
Anzeige der verfügbaren Installationen

    wsl --list --online  
    
Wechsel in Instance

    wsl -d <Distribution>    
    
Aktive Instancen anzeigen

    wsl -l -v
    
Instance beenden

    wsl --terminate <Distribution>      
    
Standard Distribution setzen

    wsl --setdefault ubuntu
    
Cloud-init 
----------

WSL unterstützt [Cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/datasources/wsl.html).

Dazu ist im Windows ein Verzeichnis `C:\Users\<User-ID>\.cloud-init` anzulegen.  

In diese werden die Cloud-init Deklarationen abgelegt. Als Dateiname ist `<Distribution>.user-data` zu verwenden, z.B. `Ubuntu-24.04.user-data`.

Beispiel für eine Cloud-init Deklaration

    #cloud-config
    users:
      - name: ubuntu
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: users, admin
        shell: /bin/bash
        lock_passwd: false
        plain_text_passwd: 'insecure'
    # login ssh and console with password
    ssh_pwauth: true
    disable_root: false
    write_files:
    - path: /etc/wsl.conf
      append: true
      content: |
        [user]
        default=ubuntu
    packages:
      - podman
      - podman-compose

Der Eintrag `write_files` um die Datei `/etc/wsl.conf` mit dem Usernamen zu ergänzen sollte immer vorhanden sein. Es sei denn man arbeitet in der WSL Distribution als `root`.

Anschliessend kann die WSL Distribution erstellt werden. Weil der User mittels Cloud-init erzeugt wird, verzichten wir auf dessen Erstellung.    

    wsl --install --no-launch -d Ubuntu-24.04
    wsl --terminate Ubuntu-24.04
    wsl --export Ubuntu-24.04 D:/WSL/ubuntu/ubuntu24.04.tar
    wsl --unregister Ubuntu-24.04    

    export IMAGE=duk
    mkdir -p ~/.cloud-init
    cp ${IMAGE}.user-data ~/.cloud-init/
    wsl --import ${IMAGE} D:/WSL/${IMAGE} D:/WSL/ubuntu/ubuntu24.04.tar --version 2 

    wsl --setdefault ${IMAGE}
    wsl cloud-init status --wait
    wsl --terminate ${IMAGE}
    wsl
    
**Debuggen**

    wsl # auf einem zweiten Terminal
    sudo tail -f /var/log/cloud-init-output.log
    
Ubuntu
------

Wird Standardmässig beim Installieren von WSL installiert. 

Podman und podman-compose installieren wir separat

    sudo apt update
    sudo apt install -y python3-pip 
    pip install podman-compose    
    
Terminal verlassen und neu starten
     
**Optional** 

`sudo -i` ohne Password ermöglichen

    echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER

Jupyter Notebook installieren und starten

    pip install jupyter

    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' 
    
Links
* [What's the recommended way of installing Podman 4 in Ubuntu 22.04?](https://askubuntu.com/questions/1414446/whats-the-recommended-way-of-installing-podman-4-in-ubuntu-22-04)     
* [Automatic setup with cloud-init](https://canonical-ubuntu-wsl.readthedocs-hosted.com/en/latest/tutorials/cloud-init/)
    
SuSe Linux 
----------

Ist eine Standard-Distribution welche direkt mittels `wsl` installiert werden kann.

    wsl --install openSUSE-Leap-15.5
    
Bei SuSe Linux fehlen ein paar nützliche PS Tools, deshalb installieren wir diese zusammen mit `podman`

    wsl -d openSUSE-Leap-15.5 
    zypper install podman psmisc python3-podman-compose  
    
Alpine Linux
------------

WSL kann jedes beliebige Linux, sofern es als `tar.gz` Datei vorliegt, starten.

Beispiel für Alpine Linux
* Download `tar.gz` Distribution von [www.alpinelinux.org](https://www.alpinelinux.org/downloads/), Distribution MINI ROOT FILESYSTEM.
* Verzeichnis anlegen für `vhdx`-Datei
* Importieren, am besten in der PowerShell

Die Befehle im einzelnen

    wget -o alpine.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.0-x86_64.tar.gz
    
    mkdir D:\WSL\alpine320
    wsl --import alpine320 D:\WSL\alpine320 alpine.tar.gz

Testen

    wsl -d alpine320

Distribution wieder löschen

    wsl --unregister alpine320
    
**Installation PodMan und Tools**

Bei Alpine Linux fehlt `lsns` deshalb installieren wir es zusammen mit PodMan

    wsl -d alpine320
    apk add util-linux podman podman-compose git

RedHat
------

Ist nicht Standardmässig vorhanden, kann aber für WSL aufbereitet werden.

* [Aufbereitung](https://developers.redhat.com/articles/2023/11/15/create-customized-rhel-images-wsl-environment#workflow) anwählen, Preview aktivieren und `tar.gz` für RedHat 8 erstellen.

    mkdir D:\WSL\rhel8wsl
    wsl --import rhel8wsl D:\WSL\rhel8wsl .\composer-api-dc519be2-43cd-49dc-bd39-09316af410fb-disk.tar.gz
    wsl -d rhel8wsl
    
Anschliesend die Packetquellen freischalten, siehe [Red Hat Subscription Management](https://docs.linuxfabrik.ch/base/system/subscription-manager.html).

    sudo subscription-manager register --username=<RedHat ID>
    sudo subscription-manager repos --enable rhel-8-for-x86_64-baseos-rpms
    
Dann die PS Tools und podman installieren.

    yum install podman docker procps psmisc iproute -y    
    
Und zum Schluss podman-compose

    pip3 install podman-compose    

* [Aufbereitung](https://developers.redhat.com/articles/2023/11/15/create-customized-rhel-images-wsl-environment#workflow)
* [Testen](https://developers.redhat.com/articles/2023/12/21/getting-started-rhel-windows-subsystem-linux#launch_the_rhel_distro_on_wsl)

Links
-----

* [Windows Terminal](https://learn.microsoft.com/en-us/windows/terminal/install)
* [Installation](https://learn.microsoft.com/en-us/windows/wsl/install#prerequisites)