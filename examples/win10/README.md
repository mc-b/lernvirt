win10
----

Die Windows Images wurden mit Packer erstellt.

Funktionieren mit KVM, QEmu, Proxmoxx etc.

Siehe
* https://github.com/mc-b/terra/tree/main/01-5-packer-windows

Installation

    helm install lab . -n win10 --create-namespace -f examples/win10/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n win10
    
Löschen

    helm uninstall lab -n win10 && kubectl delete ns win10    
    
Testen

    virtctl vnc vm-0 -n win10 
    
**Einschränkungen**

Braucht entsprechende virt Treiber ansonsten startet Windows nicht.
    
**Host vorbereiten**
    
    cd /data/images
    sudo apt install -y virt-v2v libguestfs-tools qemu-utils
    sudo systemctl start libvirtd
    export LIBGUESTFS_BACKEND=direct

VirtIO ISO herunterladen

    wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

VirtIO-Treiber kopieren    

    sudo mkdir -p /mnt/virtio
    sudo mount virtio-win.iso /mnt/iso

**Image patchen**
    
Zielverzeichnis einmal anlegen

    sudo virt-customize -a Windows10.qcow2 \
      --mkdir /Windows \
      --mkdir /Windows/Temp \
      --mkdir /Windows/Temp/Drivers

Treiber korrekt rekursiv kopieren

    sudo virt-customize -a Windows10.qcow2 \
      --copy-in /mnt/virtio/viostor/w10/amd64:/Windows/Temp/Drivers \
      --copy-in /mnt/virtio/NetKVM/w10/amd64:/Windows/Temp/Drivers

Registry-Fix für VirtIO
      
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\viostor]
    "Start"=dword:00000000
    "Group"="SCSI Miniport"
    EOF
    
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet002\Services\viostor]
    "Start"=dword:00000000
    "Group"="SCSI Miniport"
    EOF
    
    sudo virt-win-reg --merge Windows10.qcow2 <<'EOF'
    [HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\CriticalDeviceDatabase\pci#ven_1af4&dev_1001]
    "Service"="viostor"
    EOF

**templates Anpassen**

Die Datei `templates/31-vms.yaml` ist wie folgt zu ersetzen:

```yaml
{{- range $i := until (.Values.vm.count | int) }}
{{- $vm := fromYaml (include "vm.values" (dict "index" $i "values" $.Values)) }}
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-{{ $i }}
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/domain: vm-{{ $i }}
    spec:
      domain:
        machine:
          type: q35
        firmware:
          bootloader:
            efi:
              secureBoot: false
              persistent: true
        cpu:
          cores: {{ $vm.cpu }}
        resources:
          requests:
            memory: {{ $vm.memory }}
        clock:
          utc: {}
          timer:
            hpet:
              present: false
            pit:
              tickPolicy: delay
            rtc:
              tickPolicy: catchup
        devices:
          rng: {}
          disks:
            - name: rootdisk
              disk:
                bus: virtio
              bootOrder: 1
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: vm-{{ $i }}
---
{{- end }}

```

 
      
