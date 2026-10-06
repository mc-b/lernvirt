# Ubuntu PXE Stacks

Die Ubuntu-Stacks verwenden die gemeinsame PXE-Basis aus [README.md](README.md). `install-pxe.sh` bereitet Ubuntu Server für `amd64` und `arm64` vor und stellt die Autoinstall-Profile über HTTP bereit.

## Standardwerte

```bash
UBUNTU_VERSION=24.04.4
UBUNTU_CODENAME=noble
INSTALL_DISK=/dev/nvme0n1
```

Die Architektur wird beim Boot durch GRUB erkannt. Kernel und Initramfs werden per TFTP geladen, das Installationsmedium und die cloud-init-Daten per HTTP.

## Ubuntu-basierte Stacks

| Stack | Autoinstall-Profil |
|---|---|
| `ubuntu` | `user-data` |
| `cna` | `user-data-cna` |
| `cna-full` | `user-data-cna-full` |
| `platen` | `user-data-platen` |
| `reset` | `user-data-reset` |

Die Profile befinden sich unter:

```text
/var/www/html/autoinstall/
```

Die gemeinsame Ubuntu-Bootlogik liegt in `_ubuntu-install.cfg`; die einzelnen Stacks wählen primär das passende Autoinstall-Profil.

## Standard-Stack beim Einrichten wählen

Beispiel für `cna`:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | STACK=cna bash -
```

Alternativ wird die Zuordnung später in `/srv/tftp/config/rack.conf` gesetzt:

```bash
HOSTS=(
  "*|ubuntu|"
  "AA:BB:CC:DD:EE:FF|cna|"
)
```

Danach:

```bash
sudo pxe-update
```

## SSH-Key

Standardmässig verwendet die Basis den lernvirt-Schlüssel unter:

```text
/etc/lernvirt/lerncloud.pub
```

Ein eigener Public Key kann bei der Installation übergeben werden:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | \
  SSH_PUBLIC_KEY_URL="" \
  SSH_KEY_FILE=/root/.ssh/id_ed25519.pub \
  bash -
```

Oder mit einer eigenen URL:

```bash
curl -sfL https://raw.githubusercontent.com/mc-b/lernvirt/main/pxe-stack/install-pxe.sh | \
  SSH_PUBLIC_KEY_URL=https://example.org/id_ed25519.pub \
  bash -
```

## Eigenes Ubuntu-Profil

Für ein weiteres Profil kann ein neues `user-data-*` unter `/var/www/html/autoinstall/` angelegt und ein Stack erstellt werden, der die gemeinsame `_ubuntu-install.cfg` verwendet.

Beispiel Stack `kurs1`:

```text
set userdata=user-data-kurs1
source /grub/stacks/_ubuntu-install.cfg
```

Host zuweisen:

```bash
HOSTS=(
  "AA:BB:CC:DD:EE:FF|kurs1|"
)
```

Anschliessend:

```bash
sudo pxe-update
```

## Neuinstallation mit `reset`

Der Stack `reset` ignoriert bewusst einen vorhandenen lernvirt-Installationsmarker und startet erneut den Ubuntu-Autoinstall mit `user-data-reset`.
