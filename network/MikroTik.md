## MikroTik

**Vor evtl. Anpassungen muss der MikroTik-Router auf RouterOS 7.23.2 oder neuer aktualisiert werden.**

### Gerät zurücksetzen

*(Nur erforderlich, wenn keine WLAN-Verbindung möglich ist.)*

1. Die **Reset-Taste** mit einem Kugelschreiber oder einem ähnlichen Gegenstand gedrückt halten.
2. Das Gerät mit dem Strom verbinden.
3. Sobald die grüne LED zu blinken beginnt, die Reset-Taste loslassen.
4. Mit dem WLAN **`MikroTik-xxxxx`** verbinden. Wifi Key auf der Unterseite des Geräts.
5. Im Browser **[192.168.88.1](http://192.168.88.1/)** aufrufen.
6. Mit folgenden Zugangsdaten anmelden:

   * **Benutzername:** `admin`
   * **Passwort:** auf der Unterseite des Geräts

### Systemupdate durchführen

Vor dem Update empfiehlt sich ein Export der aktuellen Konfiguration:

```
/export file=before-update
/system backup save name=before-update
```

Anschliessend den Stable-Kanal auswählen, nach Updates suchen und die Installation starten:

```
/system package update
set channel=stable
check-for-updates
install
```

Der Router startet nach der Installation neu.

Danach sollte auch die RouterBOARD-Firmware aktualisiert werden:

```
/system routerboard upgrade
/system reboot
```

### WLAN-Sendeleistung

Es wird empfohlen, die WLAN-Sendeleistung des MikroTik-Routers auf **5 dBm** zu begrenzen. Dadurch wird die Funkabdeckung auf den tatsächlich benötigten Bereich beschränkt und das Risiko von Überschneidungen sowie Störungen mit benachbarten WLAN-Netzen reduziert.

    /interface/wifi/set wifi1 configuration.tx-power=5

Falls die reduzierte Sendeleistung zu einer unzureichenden WLAN-Abdeckung führt, sollte die Begrenzung wieder entfernt werden. Der Router verwendet danach erneut die automatisch ermittelte, zulässige Sendeleistung.

    /interface/wifi/set wifi1 configuration.tx-power=""
    
Anzeige der aktuellen Werte

    /interface/wifi/print detail    

### PC über Wake-on-LAN starten

Wake-on-LAN auf dem PC aktivieren. Dazu muss das Cloud-init-Script folgende Zeile enthalten:

    - curl -sfL https://raw.githubusercontent.com/mc-b/lerncloud/main/services/wake-on-lan.sh | bash -

Dann auf dem MikroTik folgenden Befehl ausführen:

    /tool wol mac=80:EE:73:EF:xx:yy interface=bridge

Falls der PC direkt an einer bestimmten Ethernet-Schnittstelle angeschlossen ist, kann statt bridge beispielsweise ether2 verwendet werden:

    /tool wol mac=80:EE:73:EF:xx:yy interface=ether2

Der MikroTik-Router sendet anschliessend ein Wake-on-LAN-Magic-Packet an den PC. Der PC sollte sich innerhalb weniger Sekunden einschalten.

### Verbindungsprobleme mit Windows 11

Bei Problemen mit Windows 11 kann der WPA2/WPA3-Mischbetrieb die Ursache sein. WPA3 deshalb testweise deaktivieren:

```
/interface wifiwave2
set [find default-name=wifi1] security.authentication-types=wpa2-psk
```

WPA3 benötigt Protected Management Frames. Bei älteren RouterOS-Versionen und bestimmten Windows-WLAN-Treibern kann der WPA2/WPA3-Übergangsmodus zu instabilen Verbindungen oder fehlgeschlagenen Anmeldungen führen.

### Statische IP-Adressen setzen

Kubernetes-Nodes sollten dauerhaft dieselbe IP-Adresse erhalten. Dafür werden auf dem DHCP-Server statische Leases anhand der MAC-Adresse eingerichtet.

    /ip dhcp-server lease
    add address=10.0.51.5 mac-address=80:EE:73:EF:xx:yy client-id="" comment="control-01"
    add address=10.0.51.6 mac-address=80:EE:73:EF:xx:yy client-id="" comment="worker-01"
    add address=10.0.51.7 mac-address=80:EE:73:EF:xx:yy client-id="" comment="worker-02"
    add address=10.0.51.8 mac-address=80:EE:73:EF:xx:yy client-id="" comment="worker-03"
    add address=10.0.51.9 mac-address=80:EE:73:EF:xx:yy client-id="" comment="worker-04"

**Wichtig:** `client-id` muss leer sein. Die Client-ID kann sich bei einer Neuinstallation des Betriebssystems ändern. Die Zuordnung erfolgt dadurch ausschliesslich über die MAC-Adresse.

Konfiguration kontrollieren:

    /ip dhcp-server lease print detail

### Ports weiterleiten

Für den externen SSH-Zugriff können unterschiedliche WAN-Ports auf Port `22` der einzelnen Nodes weitergeleitet werden.

    /ip firewall nat
    add chain=dstnat action=dst-nat protocol=tcp in-interface-list=WAN dst-port=10022 to-addresses=10.0.51.5 to-ports=22 comment="SSH control-01"
    add chain=dstnat action=dst-nat protocol=tcp in-interface-list=WAN dst-port=20022 to-addresses=10.0.51.6 to-ports=22 comment="SSH worker-01"
    add chain=dstnat action=dst-nat protocol=tcp in-interface-list=WAN dst-port=30022 to-addresses=10.0.51.7 to-ports=22 comment="SSH worker-02"
    add chain=dstnat action=dst-nat protocol=tcp in-interface-list=WAN dst-port=40022 to-addresses=10.0.51.8 to-ports=22 comment="SSH worker-03"
    add chain=dstnat action=dst-nat protocol=tcp in-interface-list=WAN dst-port=50022 to-addresses=10.0.51.9 to-ports=22 comment="SSH worker-04"

Portweiterleitungen kontrollieren:

    /ip firewall nat print where comment~"SSH"

### WireGuard Gateway einrichten

* WireGuard-Interface erstellen:
* WireGuard-IP setzen
* WireGuard-Port freigeben
* WireGuard wie ein internes Interface behandeln

```
/interface wireguard
add name=wg-gateway listen-port=51820 mtu=1420

/ip address
add address=10.1.51.1/24 interface=wg-gateway

/interface list member
add interface=wg-gateway list=LAN

/ip firewall filter
add chain=input action=accept protocol=udp dst-port=51820 in-interface-list=WAN comment="Allow WireGuard"

/ip firewall filter
move [find where comment="Allow WireGuard"] destination=[find where comment="defconf: drop all not coming from LAN"]  
```

Kontrolle und Anzeige Public Key

    /interface wireguard print detail where name=wg-gateway
    
#### WireGuard Client hinzufügen

**Windows-Client**

In der WireGuard-Anwendung:

* Tunnel hinzufügen
    * Leeren Tunnel hinzufügen
* WireGuard erzeugt automatisch: PrivateKey und den dazugehörigen öffentlichen Schlüssel.

Konfiguration vervollständigen

    [Interface]
    PrivateKey = <von WireGuard erzeugt>
    Address = 10.1.51.11/32
    
    [Peer]
    PublicKey = <Ausgabe von MikroTik oben>
    Endpoint = <Öffentliche Adresse>:51820
    AllowedIPs = 10.1.51.0/24, 10.10.0.0/24

**MikroTik**

Den öffentlichen Schlüssel, des Clients, im MikroTik eintragen

    /interface wireguard peers
    add interface=wg-gateway public-key="CLIENT-PUBLIC-KEY" allowed-address=10.1.51.11/32 comment="Client-01"
    
Kontrolle

    /interface wireguard peers print detail

Client löschen, wenn nicht mehr gebraucht

    /interface wireguard peers 
    remove [find where comment="Client-01"]
    
**SSH Zugriff via WireGuard erlauben**

    /ip service
    set ssh disabled=no port=22 address=10.1.51.0/24
    
    /ip firewall filter
    add chain=input action=accept \
        protocol=tcp dst-port=22 \
        in-interface=wg-xxx \
        src-address=10.1.51.0/24 \
        comment="SSH ueber WireGuard"
        
    /ip firewall filter move \
        [find where comment="SSH ueber WireGuard"] \
        destination=[find where comment="defconf: drop all not coming from LAN"] 
        
**Menü Zugriff via WireGuard erlauben**

    /ip firewall filter
    add chain=input \
        action=accept \
        protocol=tcp \
        dst-port=80 \
        in-interface=wg-xxx \
        src-address=10.1.51.0/24 \
        comment="WebFig HTTP ueber WireGuard"
    
    /ip firewall filter
    add chain=input \
        action=accept \
        protocol=tcp \
        dst-port=80 \
        in-interface=wg-xxx \
        src-address=10.1.51.0/24 \
        place-before=[find where comment="defconf: drop all not coming from LAN"] \
        comment="WebFig HTTP ueber WireGuard"  
        
Firewall Regeln und Reihenfolge kontrollieren

    /ip firewall filter print where chain=input
    
Fehlerhafte Regeln entfernen

    /ip firewall filter remove <No>
    
### Verschachteltete WireGuard-Verbindung

Der MikroTik-Router wird zunächst in ein bereits bestehendes Netzwerk integriert. Auf dem Client wird die vorhandene WireGuard-Verbindung zum Netz `10.1.24.0/24` eingerichtet und aktiviert. Über das WireGuard-Gateway `10.1.24.11:51820` wird anschliessend ein zweiter WireGuard-Tunnel zum MikroTik aufgebaut.

Dieser zweite Tunnel verwendet das WireGuard-Netz `10.1.51.0/24` und ermöglicht den Zugriff auf das eigentliche MikroTik-Netz `10.0.51.0/24`.

```text
PC
└─ bestehender WireGuard-Tunnel: 10.1.24.0/24
   └─ WireGuard-Gateway: 10.1.24.11:51820
      └─ zweiter WireGuard-Tunnel: 10.1.51.0/24
         └─ MikroTik-Netzwerk: 10.0.51.0/24
```

    /interface wireguard
    add name=wg-2-24 private-key="<Private Key>" mtu=1420
    
    /ip address
    add address=10.2.24.14/24 interface=wg-2-24
    
    /interface wireguard peers
    add interface=wg-2-24 public-key="<Public Key>" \
        endpoint-address=cloud.xxx.ch \
        endpoint-port=51820 \
        allowed-address=10.2.24.14/24 \
        persistent-keepalive=25s
    
    /ip firewall filter
    add chain=input \
        action=accept \
        protocol=udp \
        src-address=10.2.24.0/24 \
        dst-address=10.2.24.14 \
        in-interface=wg-2-24 \
        dst-port=51820 \
        place-before=[find where comment="defconf: drop all not coming from LAN"] \
        comment="WireGuard Handshake ueber wg-2-24"
        
Hinweis: besser Port forwards verwenden.        

### Nützliche Befehle

Alle bezogenen DHCP-Adressen anzeigen

    /ip dhcp-server lease print

Alle konfigurierten IPv4-Adressen anzeigen:

    /ip address print

DHCP-Client am WAN-Port anzeigen:

    /ip dhcp-client print detail

Aktuelle RouterOS-Version anzeigen:

    /system resource print

Installierte Pakete anzeigen:

    /system package print


