## AI Server

### GPU-Schnelltest

Zur Verifikation, dass die GPU korrekt erkannt und angesprochen werden kann, sollten folgende Tests durchgeführt werden.

    podman run --rm --device nvidia.com/gpu=all ubuntu nvidia-smi -L

„GPU 0“ = erste GPU. Bei mehreren Karten erscheinen GPU 1, GPU 2, usw.

Bei Fehlern prüfen:

    nvidia-ctk --version
    nvidia-ctk cdi list

Wenn keine Geräte gelistet sind, ist keine CDI-Konfiguration (Container Device Interfaces) vorhanden.

Host unabhängig testen:

    nvidia-smi

Wenn hier bereits ein Fehler erscheint, liegt das Problem beim Treiber und nicht bei Podman.

**Hinweis**: nvidia-smi (NVIDIA System Management Interface) ist ein CLI-Werkzeug zur Abfrage des Zustands und der Auslastung von NVIDIA-GPUs über den installierten Treiber.

---

### Open WebUI mit integriertem Ollama-Support

Open WebUI ist eine browserbasierte Oberfläche zur Interaktion mit lokalen oder zentral betriebenen Large-Language-Models und stellt eine OpenAI-kompatible API-Anbindung bereit.

Diese Installationsmethode verwendet ein einzelnes Container-Image, das Open WebUI und Ollama gemeinsam bereitstellt. Dadurch ist eine vereinfachte Einrichtung mit einem einzigen Befehl möglich. Je nach Hardware-Konfiguration ist der passende Befehl zu wählen.
Bei Verwendung einer NVIDIA-GPU kann der Container mit GPU-Zugriff wie folgt gestartet werden. Zusätzlich wird neben dem WebUI-Port (3000) auch der OpenAI-/Ollama-API-Port (11434) weitergeleitet:

    podman rm -f open-webui
    podman run -d -p 3000:8080 -p 11434:11434 \
      --device nvidia.com/gpu=all \
      -v ollama:/root/.ollama \
      -v open-webui:/app/backend/data \
      -e OLLAMA_HOST=0.0.0.0:11434 \
      --name open-webui --restart=always \
      ghcr.io/open-webui/open-webui:ollama

Nach der Installation ist Open WebUI mittels Port 3000 erreichbar.
Die OpenAI-kompatible API von Ollama steht auf Port 11434 zur Verfügung (muss noch im UI freigeschaltet werden).

Folgende Modelle laden `llama3.1:8b-instruct-q4_K_M` und `gemma3:12b`

**Prompt**: `wie bauche ich einen Web server in Python`.

**Tipp**: `watch nvidia-smi` in Console ausführen um GPU Verwendung anzuzeigen.

**Testen der Open WebUI Container Umgebung**

Ausgabe der GPU Devices

    podman exec -it open-webui bash -lc 'ls -l /dev/nvidia* 2>/dev/null || true; ls -l /dev/dri 2>/dev/null || true'
    
Direktes Laden eines Modells in Ollama und Prompt    

    podman exec -it open-webui bash -lc 'ollama pull llama3.2:1b && ollama run llama3.2:1b "Schreibe 2 Saetze ueber GPUs."'

**Links**:

* [Installing Open WebUI with Bundled Ollama Support](https://github.com/open-webui/open-webui?tab=readme-ov-file#installing-open-webui-with-bundled-ollama-support)

