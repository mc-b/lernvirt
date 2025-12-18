Multus
------

Multus in KubeVirt ermöglicht es virtuellen Maschinen, mehrere Netzwerkschnittstellen zu verwenden. Dadurch können VMs gleichzeitig mit verschiedenen Netzwerken (z. B. Pod-Netzwerk und zusätzlichen VLANs oder SR-IOV-Netzen) verbunden werden. Das ist besonders nützlich für komplexe Netzwerk-Setups und für die Trennung von Daten- und Management-Traffic.

**Alle Angaben sind nur rudimentär getestet, können Fehler enthalten und ohne jegliche Gewähr!**

Falls die VMs ein eigenes Netzwerk bekommen sollen (dann sehen sie aber die Pods nicht mehr!), multus installieren

    microk8s enable community
    microk8s enable multus
  
Dann Problem die PV binden nicht mehr. Lösung neue Storage Class 
  
    kubectl apply -f - <<EOF
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: hostpath-immediate
    provisioner: microk8s.io/hostpath
    volumeBindingMode: Immediate
    reclaimPolicy: Retain
    EOF 
    
Und DataSource erweitern:

    apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: vm-{{ $i }}
    spec:
      source:
        http:
          url: {{ $vm.image.url }}
      pvc:
        storageclass: hostpath-immediate
        accessModes:
          - ReadWriteOnce 

Eigenes multus Netzwerk anlegen (in templates pro Namespace)

    apiVersion: k8s.cni.cncf.io/v1
    kind: NetworkAttachmentDefinition
    metadata:
      name: bridge-net
    spec:
      config: |
        {
          "cniVersion": "0.3.1",
          "type": "bridge",
          "ipam": {
            "type": "host-local",
            "subnet": "10.1.0.0/24",
            "rangeStart": "10.1.0.100",
            "rangeEnd": "10.1.0.200"
          }
        }   

          
Anschliessend das Template der VMs ändern

          interfaces:
            - name: default
              bridge: {}
      networks:
        - name: default
          multus:
            networkName: bridge-net  
            
Damit bekommt jede VM eine eigene IP-Adresse statt `10.0.2.2`.                    
                    