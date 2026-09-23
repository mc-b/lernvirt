# Luckfox PicoKVM

![](https://www.luckfox.com/image/cache/catalog/development-board/Luckfox-PicoKVM/Luckfox-PicoKVM-1-544x544.jpg)

Quelle: Luckfox
- - - 

Der [Luckfox PicoKVM](https://wiki.luckfox.com/Luckfox-PicoKVM) ist eine kompakte KVM-over-IP-Lösung auf Basis eines eingebetteten Linux-Systems. Er ermöglicht den Fernzugriff auf Bildschirmausgabe, Tastatur und Maus eines angeschlossenen Rechners und eignet sich damit für Administration, Wartung und Remote-Zugriff auf Systeme ohne laufendes Betriebssystem.

Die wichtigsten Funktionen des [Luckfox PicoKVM](https://wiki.luckfox.com/Luckfox-PicoKVM) sind:

* **KVM-over-IP** – Fernzugriff auf Bildschirm, Tastatur und Maus über den Webbrowser. 
* **Full-HD-Videoübertragung** bis **1920 × 1080 bei 60 Hz**, mit H.264/H.265-Encoding. 
* **Tastatur- und Mausemulation** über USB, inklusive relativem und absolutem Mausmodus. 
* **BIOS-/UEFI-Zugriff**, da die KVM-Funktion unabhängig vom Betriebssystem des Zielrechners arbeitet. 
* **Virtual Media** zur Einbindung von ISO-, IMG-, QCOW2-, WDI- und VMDK-Images als virtuelles USB-Laufwerk. 
* **Remote-Installation von Betriebssystemen** über eingebundene Installationsmedien, siehe [Serverinstallation auf Bare-Metal-Hardware](../autoinstall/README.md)
* **Audioübertragung** vom Zielsystem über USB Audio Class. 
* **Dateiübertragung** zwischen lokalem Rechner und Zielsystem. 
* **Remote-Zugriff über VPN-/Overlay-Netzwerke**, unter anderem Tailscale, WireGuard, ZeroTier und NetBird. 
* **Wake-on-LAN** zum Einschalten unterstützter Systeme. 
* **Remote Power Control** über die optionale PicoKVM-Ext-Erweiterung. 
* **Ethernet-Anschluss mit 10/100 Mbit/s** sowie DHCP oder statischer IP-Konfiguration. 
* **SSH-Zugriff** auf das zugrunde liegende Embedded-Linux-System. 

### Tailscale als Client

Als Alternative zur in der Luckfox-Dokumentation beschriebenen Anmeldung kann Tailscale auch **als Client ohne interaktiven Login** eingerichtet werden. Dazu wird der PicoKVM mit einem vorab erzeugten **Auth Key** direkt dem Tailnet hinzugefügt und kann anschliessend dauerhaft automatisch verbinden.

    cd /userdata
    curl -LO https://pkgs.tailscale.com/stable/tailscale_1.102.4_arm.tgz
    gzip -dc tailscale_1.102.4_arm.tgz | tar xvf -
    cd tailscale_1.102.4_arm
    mv tailscaled tailscale /usr/bin

Tailscale als Service einrichten und starten

```bash
cat >/etc/init.d/S90tailscale <<'EOF'
#!/bin/sh

DAEMON=/usr/bin/tailscaled
STATE=/var/lib/tailscale/tailscaled.state
PIDFILE=/var/run/tailscaled.pid
LOG=/var/log/tailscaled.log

case "$1" in
    start)
        echo "Starting tailscaled"

        mkdir -p /var/lib/tailscale
        mkdir -p /var/run

        $DAEMON \
            --state=$STATE \
            >>$LOG 2>&1 &

        echo $! > $PIDFILE
        ;;

    stop)
        echo "Stopping tailscaled"

        if [ -f "$PIDFILE" ]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            rm -f "$PIDFILE"
        else
            killall tailscaled 2>/dev/null
        fi
        ;;

    restart)
        "$0" stop
        sleep 1
        "$0" start
        ;;

    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
EOF

chmod +x /etc/init.d/S90tailscale
/etc/init.d/S90tailscale start
```

Tailscale aktivieren

    TS_AUTHKEY="..."
    TS_HOSTNAME=picokvm
    tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --accept-routes=false --reset --advertise-tags=tag:lerncloud
    
    
