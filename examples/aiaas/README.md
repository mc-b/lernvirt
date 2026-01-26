AI as a Service
---------------

![](../images/jupyterlab.png)

---

Eine dedizierte virtuelle Maschine (AI-Server) stellt den KI-Dienst bereit. Darauf laeuft **Ollama als System-Service** und verwaltet **zwei KI-Modelle**, die bedarfsgesteuert geladen und wieder entladen werden. Die Modelle werden zentral betrieben und stehen allen Clients ueber eine **OpenAI-kompatible API** zur Verfuegung.

Alle weiteren virtuellen Maschinen dienen als **Client-Umgebungen**. Sie enthalten **Jupyter Lab Notebooks mit OpenAI-Runtime** und greifen ausschliesslich ueber die API auf den zentralen KI-Dienst zu. Lokale Modellinstallation oder GPU-Zugriff auf den Client-VMs ist nicht erforderlich.

Dieses Setup trennt **KI-Infrastruktur** und **Anwendungsentwicklung** klar voneinander und eignet sich besonders fuer Schulungs- und Laborumgebungen.

Installation

    helm install aiaas . -n aiaas --create-namespace -f examples/aiaas/values.yaml
    
Kontrolle

    kubectl get sc,pv,pvc,dv,vm,vmi -n aiaas
    
Löschen

    helm uninstall aiaas -n aiaas && kubectl delete ns aiaas    
    
Testen

    virtctl console vm-0 -n aiaas 

---

## Ansprechen aus VSCode (mit Continue) 

![](../images/vscode.png)

---

Continue in VS Code kann nur auf localhost zugreifen. Damit trotzdem eine Ollama-Instanz auf einem Remote-Server verwendet werden kann, wird ein SSH-Port-Forwarding eingesetzt.

**Voraussetzungen**

* Linux-Server oder VM mit laufender Ollama-Instanz
* Ollama hört auf Port `11434`
* SSH-Zugang (Host, Benutzer, SSH-Key)
* Lokal installierter VS Code

**Schritt 1: SSH-Port-Forwarding einrichten**

Auf dem lokalen Rechner wird eine SSH-Verbindung mit Port-Weiterleitung aufgebaut:

    ssh -L 11434:localhost:11434 -i <ssh-key> ubuntu@<host>

**Schritt 2: VS Code starten**

VS Code wird lokal gestartet.

**Schritt 3: Continue Extension installieren**

* Öffnen des Extension Marketplace in VS Code
* Installation der Extension **Continue**

Nach der Installation steht Continue im Editor als Chat View (Ctrl+L) zur Verfügung.

**Schritt 4: Continue für Ollama konfigurieren**

In der Continue-Konfiguration wird Ollama als Provider eingetragen.

**Schritt 5: Nutzung von Continue**

Continue kann nun direkt in VS Code verwendet werden, zum Beispiel für:

* Erklärungen von Code
* Unterstützung beim Schreiben von Code
* Vorschläge für Verbesserungen oder Refactorings

Die KI läuft auf dem Server, erscheint für Continue jedoch als lokaler Dienst.

**Hinweis**: für die Einrichtung der Server Seite siehe [FAQ - SSH nur Port Weiterleitung](https://github.com/mc-b/lernvirt/blob/main/FAQ.md#ssh-nur-port-weiterleitung-ohne-shell)

---

## Jupyter Lab

Im JupyterLab stehen einige Notebooks zur Verfügung, die zur Demonstration der AI-Lernumgebung dienen.

Die JupyterLab Umgebung läuft auf dem Port **32188**.


### Chat

![](../images/chat.png)

**Notebooks**: 
* [data/chat/ollama.ipynb](chat/ollama.ipynb) - Einfacher Chat mit beiden Ollama LLM Modellen
* [data/chat/openai.ipynb](chat/openai.ipynb) - Wir bauen eine kleine Webanwendung mittels dem OpenAI API

### RAG - Retrieval Augmented Generation 

RAG (Retrieval Augmented Generation) ist ein Ansatz in der KI, bei dem ein Sprachmodell vor der Antwort relevante Informationen aus externen Wissensquellen abruft und diese in die Generierung der Antwort einbezieht.

![](../images/rag.png)

---

**Notebooks**: 
* [data/rag/rag_ollama_chroma.ipynb](rag/rag_ollama_chroma.ipynb) - Bereitet ein Mouser Magazine als RAG Inhalt auf
* [data/rag/openai-vectorstore.ipynb](rag/openai-vectorstore.ipynb) - Bereitet das Projekt lernmaas für RAG auf und stellt gezielt Fragen.


### MCP - Model Context Protocol

Model Context Protocol ist ein offenes Protokoll, mit dem Tools, Dateien, Repositories, Datenbanken oder APIs strukturiert an ein LLM angebunden werden.

Ollama liefert dabei nur die Text-Generierung; Kontext, Tools und Ressourcen kommen über MCP von aussen.

![](../images/mcp.png)

![](../images/mcp-chat.png)

---

**Notebooks**:
* [data/mcp/mcp-server.ipynb](mcp/mcp-server.ipynb) - MCP Server Applikation, zuerst starten
* [data/mcp/mcp-client.ipynb](mcp/mcp-client.ipynb) - einfacher MCP Client ohne AI.
* [data/mcp/mcp-ai-client.ipynb](mcp/mcp-ai-client.ipynb) - MCP Client in Kombination mit AI

