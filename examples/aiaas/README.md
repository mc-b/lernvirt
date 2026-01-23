AI as a Service
---------------

Eine dedizierte virtuelle Maschine stellt den KI-Dienst bereit.
Darauf laeuft **Ollama als System-Service** und verwaltet **zwei KI-Modelle**, die bedarfsgesteuert geladen und wieder entladen werden. Die Modelle werden zentral betrieben und stehen allen Clients ueber eine **OpenAI-kompatible API** zur Verfuegung.

Alle weiteren virtuellen Maschinen dienen als **Client-Umgebungen**.
Sie enthalten **Jupyter Notebooks mit OpenAI-Runtime** und greifen ausschliesslich ueber die API auf den zentralen KI-Dienst zu. Lokale Modellinstallation oder GPU-Zugriff auf den Client-VMs ist nicht erforderlich.

Dieses Setup trennt **KI-Infrastruktur** und **Anwendungsentwicklung** klar voneinander und eignet sich besonders fuer Schulungs- und Laborumgebungen.


Installation

    helm install aiaas . -n aiaas --create-namespace -f examples/aiaas/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n aiaas
    
Löschen

    helm uninstall aiaas -n aiaas && kubectl delete ns aiaas    
    
Testen

    virtctl console vm-0 -n aiaas 
