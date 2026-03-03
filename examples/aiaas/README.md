AI as a Service
---------------

![](../images/jupyterlab.png)

---

Steht ein dedizierter AI-Rechner (z. B. NVIDIA DGX Spark) zur Verfügung, wird dieser gemäss [SERVER.md](SERVER.md) als zentraler KI-Server eingerichtet. Die KI-Dienste laufen dabei als Podman-Container mit direktem GPU-Zugriff. Die Installation wird anschliessend bei VSCode fortgesetzt.

**Andernfalls** wird eine dedizierte virtuelle Maschine (AI-Server) bereitgestellt, welche den KI-Dienst in der VM betreibt. Auf dieser läuft Ollama als System-Service und verwaltet zwei KI-Modelle, die bedarfsgesteuert geladen und wieder entladen werden. 

Alle weiteren virtuellen Maschinen dienen als **Client-Umgebungen**. Sie enthalten **Jupyter Lab Notebooks mit OpenAI-Runtime** und greifen ausschliesslich ueber die API auf den zentralen KI-Dienst zu. Lokale Modellinstallation oder GPU-Zugriff auf den Client-VMs ist nicht erforderlich.

Dieses Setup trennt **KI-Infrastruktur** und **Anwendungsentwicklung** klar voneinander und eignet sich besonders fuer Schulungs- und Laborumgebungen.

Host spezifische Werte festlegen

    HELM_VALUES_HOST=hosts/<host>.yaml

Installation

    helm install aiaas . -n aiaas --create-namespace -f examples/aiaas/values.yaml -f ${HELM_VALUES_HOST}
    
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

**Links**:

* [Vibe Coding in VS Code](https://build.nvidia.com/spark/vibe-coding/instructions)

---

## Jupyter Lab

Im JupyterLab stehen einige Notebooks zur Verfügung, die zur Demonstration der AI-Lernumgebung dienen.

**Diese sollten regelmässig aktualisiert werden**.

    cd data && curl -L https://github.com/mc-b/lernvirt/archive/refs/heads/main.tar.gz | tar xz --strip-components=3 lernvirt-main/examples/aiaas --exclude='*/'

Die JupyterLab Umgebung läuft auf dem Port **32188**.

Neben der Standard Jupyter Umgebung, stehen folgende weitere zur Verfügung:
* `~/.ai` - OpenAI API
* `~/.rag` - RAG - Retrieval Augmented Generation (Libraries: chromadb pypdf requests tqdm)
* `~/.mcp` - MCP - Model Context Protocol (Libraries: mcp requests openai)
* `~/.agent` - Agenten-Workflows - LlamaIndex (Libraries: llama-index llama-index-llms-ollama llama-index-embeddings-huggingface)

Fehlende Libraries können, in der Shell, wie folgt Nachinstalliert werden, z.B.:

    source ~/.ai/bin/activate
    pip install requests

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

**Links**:

* [Docling](https://www.docling.ai/)

### MCP - Model Context Protocol

Model Context Protocol ist ein offenes Protokoll, mit dem Tools, Dateien, Repositories, Datenbanken oder APIs strukturiert an ein LLM angebunden werden.

Ollama liefert dabei nur die Text-Generierung; Kontext, Tools und Ressourcen kommen über MCP von aussen.

![](../images/mcp.png)

![](../images/mcp-chat.png)

**Notebooks**:
* [data/mcp/mcp-server.ipynb](mcp/mcp-server.ipynb) - MCP Server Applikation, zuerst starten
* [data/mcp/mcp-client.ipynb](mcp/mcp-client.ipynb) - einfacher MCP Client ohne AI.
* [data/mcp/mcp-ai-client.ipynb](mcp/mcp-ai-client.ipynb) - MCP Client in Kombination mit AI

**Links:**
* [5 MCP-Server für mehr Cloud Automation](https://www.computerwoche.de/article/4133146/5-mcp-server-fur-mehr-cloud-automation.html)

---

### Agenten-Workflows - LlamaIndex

LlamaIndex ist ein Python-Framework zur Entwicklung von Retrieval-Augmented-Generation-Anwendungen, das eigene Datenquellen strukturiert indexiert und mit grossen Sprachmodellen für kontextbasierte Abfragen und Agenten-Workflows verbindet.

**Einfacher Agent** der mithilfe eines Tools einfache Multiplikationen durchführen kann:

    def multiply(a: float, b: float) -> float:
        """Useful for multiplying two numbers."""
        return a * b
    agent = FunctionAgent(
        tools=[multiply],
        llm=Ollama(
            model="llama3.1:8b-instruct-q4_K_M",
            request_timeout=360.0,
            context_window=8000,
        ),
        system_prompt="You are a helpful assistant that can multiply two numbers.",
    )
    async def main():
        response = await agent.run("What is 1234 * 4567?")
        return response

**Chat History**

    agent = FunctionAgent(
        llm=Ollama(
            model="llama3.1:8b-instruct-q4_K_M",
            request_timeout=360.0,
            context_window=8000,
        ),
    )
    # run agent with context
    response = await agent.run("My name is Logan", ctx=ctx)
    response = await agent.run("What is my name?", ctx=ctx)

**RAG Funktionen**

    search_documents = https://raw.githubusercontent.com/run-llama/llama_index/main/docs/examples/data/paul_graham/paul_graham_essay.txt -O data/paul_graham_essay.txt
    
    agent = AgentWorkflow.from_tools_or_functions(
        [multiply, search_documents],
        llm=Settings.llm,
        system_prompt="""You are a helpful assistant that can perform calculations
        and search through documents to answer questions.""",
    )
    async def main():
        response = await agent.run(
            "What did the author do in college? Also, what's 7 * 8?"
        )
        return response   

**Notebooks**:
* [data/agent/Basic.ipynb](agent/Basic.ipynb) - Einfacher Agent
* [data/agent/ChatHistory.ipynb](agent/ChatHistory.ipynb) - Chat History
* [data/agent/RAG.ipynb](agent/RAG.ipynb) - RAG Funktionen

### Links

* [KI Kompetenz (TBZ)](https://gitlab.com/ch-tbz-it/Stud/allgemein/ki-kompetenz)

