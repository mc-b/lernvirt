## AI Server

**Damit AI Server und die Client Notebooks zusammen sauber funktionieren, sollten diese auf dem Client regelmässig aktualisiert werden, siehe [Jupyter Lab](https://github.com/mc-b/lernvirt/tree/main/examples/aiaas#jupyter-lab).**

### Kubernetes

* [k3s](Server-k3s.md)
* [microk8s](Server-microk8s.md)

**ACHTUNG**: es funktioniert nur jeweils eine Variante, d.h. `k3s` oder `microk8s`.

Die `rPodman Sandbox` kann parallel zu Kubernetes betrieben werden.

### Online GPUs Umgebungen

* [Nvidia ab CHF 1.50 pro Stunde](https://brev.nvidia.com/) 

### rPodman Sandbox

![](../images/rpodman.png)

- - -

Diese rpodman Container-Sandbox stellt eine kontrollierte, auf Ubuntu basierende Laufzeitumgebung mit klar definiertem Befehlssatz dar, die der isolierten und überwachten Ausführung von Container-Workloads mittels `podman` dient.

Neben dem bewusst eingeschränkten Befehlssatz sind keine direkten Filesystem-Mounts zulässig; persistente oder gemeinsam genutzte Daten werden stattdessen über dedizierte Volumes eingebunden.

    podman volume create mydata
    podman run --rm -v mydata:/app/data ubuntu ls -l /app/data

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

### LLMFit

Systemcheck für KI: Dieses Tool zeigt dir, welches Sprachmodell auf deiner Hardware läuft.

**Links**::
* [GitHub LMMFit](https://github.com/AlexsJones/llmfit) 
* [Container](https://github.com/AlexsJones/llmfit/pkgs/container/llmfit)
* [Artikel](https://t3n.de/news/systemcheck-ki-tool-welches-sprachmodell-laeuft-auf-deiner-hardware-1731942/)

---

### Open WebUI mit integriertem Ollama-Support

Open WebUI ist eine browserbasierte Oberfläche zur Interaktion mit lokalen oder zentral betriebenen Large-Language-Models und stellt eine OpenAI-kompatible API-Anbindung bereit.

Diese Installationsmethode verwendet ein einzelnes Container-Image, das Open WebUI und Ollama gemeinsam bereitstellt. Dadurch ist eine vereinfachte Einrichtung mit einem einzigen Befehl möglich. Je nach Hardware-Konfiguration ist der passende Befehl zu wählen.

Bei Verwendung einer NVIDIA-GPU kann der Container mit GPU-Zugriff wie folgt gestartet werden. Zusätzlich wird neben dem WebUI-Port (3000) auch der OpenAI-/Ollama-API-Port (11434) weitergeleitet:

    podman volume create ollama
    podman volume create open-webui

    podman rm -f open-webui
    podman run -d -p 3000:8080 -p 11434:11434 \
      --device nvidia.com/gpu=all \
      -v ollama:/root/.ollama \
      -v open-webui:/app/backend/data \
      -e OLLAMA_HOST=0.0.0.0:11434 \
      --name open-webui --restart=always \
      --ulimit memlock=-1 \
      --ulimit stack=67108864 \
      ghcr.io/open-webui/open-webui:ollama

Nach der Installation ist Open WebUI mittels Port 3000 erreichbar.
Die OpenAI-kompatible API von Ollama steht auf Port 11434 zur Verfügung.

Folgende Modelle laden `llama3.1:8b-instruct-q4_K_M` und `gemma3:12b`

**Prompt**: `wie bauche ich einen Web server in Python`.

**Tipp**: `watch nvidia-smi` in Console ausführen um GPU Verwendung anzuzeigen.

**Testen der Open WebUI Container Umgebung**

Ausgabe der GPU Devices

    podman exec -it open-webui bash -lc 'ls -l /dev/nvidia* 2>/dev/null || true; ls -l /dev/dri 2>/dev/null || true'
    
Direktes Laden eines Modells in Ollama und Prompt    

    podman exec -it open-webui bash -lc 'ollama pull llama3.2:1b && ollama run llama3.2:1b "Schreibe 2 Saetze ueber GPUs."'
    
Testen der Kommunikationsverbindung

    curl -sS http://localhost:11434/api/tags
    curl -sS http://localhost:11434/v1/models    

**Links**:

* [Installing Open WebUI with Bundled Ollama Support](https://github.com/open-webui/open-webui?tab=readme-ov-file#installing-open-webui-with-bundled-ollama-support)
---

### SGLang 

NVIDIA-optimierter Container explizit für DGX Spark.

NVIDIA bietet für DGX Spark/Blackwell einen “optimierten SGLang NGC Container” und dokumentiert das als empfohlenes Setup für einen einzelnen Spark-Node.

Wenn du viel mit Chat-Serving/Tool-Use/Control-Flows arbeitest, ist SGLang oft sehr angenehm, und hier hast du den Bonus “NVIDIA-tuned for Spark”.

Anbei Beispiele mit optimierten Parametern für DGX Spark. Die Erklärungen dazu findet ihr in den Notebooks

    podman volume create sglang-cache

    podman run -d --rm \
      --device nvidia.com/gpu=all \
      -p 30000:30000 \
      -v sglang-cache:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      python3 -m sglang.launch_server \
        --model-path Qwen/Qwen2.5-0.5B-Instruct \
        --host 0.0.0.0 \
        --port 30000 \
        --trust-remote-code \
        --tp 1 \
        --attention-backend flashinfer \
        --mem-fraction-static 0.10 \
        --max-running-requests 1 \
        --chunked-prefill-size 1 \
        --cuda-graph-max-bs 1 \
        --max-prefill-tokens 2048
    
Einfache Abfrage in einem zweiten Terminal
   
    curl -X POST http://localhost:30000/generate \
      -H "Content-Type: application/json" \
      -d '{
          "text": "What does NVIDIA love?",
          "sampling_params": {
              "temperature": 0.7,
              "max_new_tokens": 100
          }
      }'

temperature
* Dieser Wert bestimmt, wie kreativ oder vorhersehbar die Antwort des Modells ist: ein niedriger Wert führt zu eher sicheren, ähnlichen Antworten, ein höherer Wert zu abwechslungsreicheren und manchmal überraschenderen Formulierungen.

max_new_tokens
* Dieser Wert legt fest, wie lang die Antwort maximal werden darf, indem er die Anzahl der neuen Wörter bzw. Wortteile begrenzt, die das Modell erzeugen darf.
      
Abfragen mittels OpenAPI API sind ebenfalls möglich.

**Weiter Umgebungen/Modelle**          

    podman volume create sglang-cache1
        
    podman run -d --rm \
      --device nvidia.com/gpu=all \
      -p 30001:30000 \
      -v sglang-cache1:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      python3 -m sglang.launch_server \
        --model-path HuggingFaceTB/SmolLM2-1.7B-Instruct \
        --host 0.0.0.0 \
        --port 30000 \
        --trust-remote-code \
        --tp 1 \
        --attention-backend flashinfer \
        --mem-fraction-static 0.10 \
        --max-running-requests 1 \
        --chunked-prefill-size 1 \
        --cuda-graph-max-bs 1 \
        --max-prefill-tokens 2048  
        
        
    podman volume create sglang-cache2        
    podman run -d --rm \
      --device nvidia.com/gpu=all \
      -p 30002:30000 \
      -v sglang-cache2:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      python3 -m sglang.launch_server \
        --model-path Qwen/Qwen2.5-Coder-0.5B \
        --host 0.0.0.0 \
        --port 30000 \
        --trust-remote-code \
        --tp 1 \
        --attention-backend flashinfer \
        --mem-fraction-static 0.10 \
        --max-running-requests 1 \
        --chunked-prefill-size 1 \
        --cuda-graph-max-bs 1 \
        --max-prefill-tokens 2048
        
    podman volume create sglang-cache3        
    podman run -d --rm \
      --device nvidia.com/gpu=all \
      -p 30003:30000 \
      -v sglang-cache3:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      python3 -m sglang.launch_server \
        --model-path HuggingFaceTB/SmolLM2-135M-Instruct \
        --host 0.0.0.0 \
        --port 30000 \
        --trust-remote-code \
        --tp 1 \
        --attention-backend flashinfer \
        --mem-fraction-static 0.10 \
        --max-running-requests 1 \
        --chunked-prefill-size 1 \
        --cuda-graph-max-bs 1 \
        --max-prefill-tokens 2048 
        
        
    podman volume create sglang-cache4       
    podman run -d --rm \
      --device nvidia.com/gpu=all \
      -p 30004:30000 \
      -v sglang-cache4:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      python3 -m sglang.launch_server \
        --model-path TinyLlama/TinyLlama-1.1B-Chat-v1.0 \
        --host 0.0.0.0 \
        --port 30000 \
        --trust-remote-code \
        --tp 1 \
        --attention-backend flashinfer \
        --mem-fraction-static 0.10 \
        --max-running-requests 1 \
        --chunked-prefill-size 1 \
        --cuda-graph-max-bs 1 \
        --max-prefill-tokens 2048   

**Interaktive Umgebung**
        
    podman volume create sglang-cache5           
    podman run -it --rm \
      --device nvidia.com/gpu=all \
      -p 30005:30000 \
      -v sglang-cache5:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/lmsysorg/sglang:v0.5.9-cu130-arm64-runtime \
      bash  

Im Container

    git clone https://github.com/mjhermanson-nv/sglang-brevdev.git
    cd sglang-brevdev
    
    pip install marimo
    python3 01_send_request.py
    
Weitere [Dokumentation](https://github.com/mjhermanson-nv/sglang-brevdev).


**Links**:
* [Install and use SGLang on DGX Spark](https://build.nvidia.com/spark/sglang/overview)
* [Homepage](https://docs.sglang.io/)
* [Container Image Beschreibung](https://docs.nvidia.com/deeplearning/frameworks/sglang-release-notes/rel-26-02.html)

---

### vLLM

vLLM ist eine schnelle und einfach zu nutzende Bibliothek für die Inferenz und das Bereitstellen (Serving) grosser Sprachmodelle. Sie optimiert die Ausführung auf GPUs durch effizientes Speichermanagement (z. B. PagedAttention) und ermöglicht hohe Durchsätze bei geringer Latenz, sowohl im Batch- als auch im Online-Betrieb.


    podman volume create vllm-cache

    podman run -it --rm --device nvidia.com/gpu=all \
      -p 8000:8000 \
      --ipc=host \
      --name vllm \
      --ulimit memlock=-1 \
      --ulimit stack=67108864 \
      -v vllm-cache:/root/.cache/huggingface \
      -v /tmp:/tmp \
      docker.io/vllm/vllm-openai:cu130-nightly \
      --model Qwen/Qwen2.5-3B-Instruct \
      --gpu-memory-utilization 0.10 \
      --max-model-len 4096 \
      --max-num-seqs 16 \
      --max-num-batched-tokens 4096 \
      --enable-chunked-prefill
    
Die OpenAI-kompatible API von vLLM steht auf Port 8000 zur Verfügung    
    
**Hinweis**: Das starten von vLLM kann mehrere Minuten dauern. 

**Testen der vLLM Container Umgebung**

Ausgabe der GPU Devices

    podman exec -it vllm bash -lc 'ls -l /dev/nvidia* 2>/dev/null || true; ls -l /dev/dri 2>/dev/null || true'

Ausgabe des gecachten Models (`hf` ist das Hugging Face CLI)

    podman exec -it vllm hf cache scan
    
Testen der Kommunikationsverbindung

    curl -sS http://localhost:8000/v1/models           

**Links**:
* [Using Docker](https://docs.vllm.ai/en/stable/deployment/docker/#pre-built-images)
* [Install and use vLLM on DGX Spark](https://build.nvidia.com/spark/vllm/overview)

---

### NVIDIA NIM 

NIM ist im Prinzip ein vorkonfigurierter, vereinheitlichter Deployment-Weg, der u.a. auf Triton basiert und je nach Modell/Setup TensorRT bzw. vLLM als Backend nutzt.

Modell + optimierte Inference-Engine + API-Schicht + CUDA/TensorRT-Stack sind in einem getesteten Container gebündelt 

Modell:
NVIDIA NIM gemma-3-1b-it

Ziel: gemma-3-1b-it als NIM Microservice auf einer DGX Spark mit Podman starten. Der Modell-Cache wird als Podman Volume persistiert.

1. Login bei NGC

    podman login nvcr.io
    Username: $oauthtoken
    Password: <NGC_API_KEY>

2. Container Image laden

    podman pull nvcr.io/nim/meta/llama-3.1-8b-instruct:latest

3. Persistentes Volume für Modell-Cache anlegen

    podman volume create nim-cache

Das Volume wird im Container nach /opt/nim/.cache gemountet. Dadurch bleibt das Modell nach Container-Neustarts erhalten.

4. Prüfen ob das Container Image für ARM64 Architektur verfügbar ist

    podman manifest inspect nvcr.io/nim/meta/llama-3.1-8b-instruct-dgx-spark:latest

5. Container starten 

    podman run --rm -d \
        --name nvidia-nim \
        --ulimit memlock=-1 \
        --ulimit stack=67108864 \
        --shm-size=8g \
        --device nvidia.com/gpu=all \
        -e NGC_API_KEY=<DEIN_KEY> \
        -v nim-cache:/opt/nim/.cache \
        -p 8010:8000 \
        nvcr.io/nim/meta/llama-3.1-8b-instruct-dgx-spark:latest
        
Das Model lässt sich über Port 8010 und mit Namen `meta/llama-3.1-8b-instruct` ansprechen.
        
**ACHTUNG**: braucht 60 GB RAM!     
                
Beim ersten Start wird das Modell in das Volume geladen. Weitere Starts erfolgen ohne erneuten Download.

6. Funktionstest

    curl -sS http://localhost:8010/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{ "model": "meta/llama-3.1-8b-instruct", "messages": [ {"role": "user", "content": "Erkläre kurz was eine GPU ist."} ] }'

**Links**:
* [Overview of NVIDIA NIM for Large Language Models (LLMs)](https://docs.nvidia.com/nim/large-language-models/latest/introduction.html)
* [A Simple Guide to Deploying Generative AI with NVIDIA NIM](https://developer.nvidia.com/blog/a-simple-guide-to-deploying-generative-ai-with-nvidia-nim/)
* [Deploy a NIM on Spark](https://build.nvidia.com/spark/nim-llm)
* [NVIDIA NIM for Developers](https://developer.nvidia.com/nim?sortBy=developer_learning_library)
* [NGC Catalog](https://catalog.ngc.nvidia.com/)

---

### TensorRT-LLM 

Für maximale Inference-Performance auf NVIDIA-Hardware ist TensorRT-LLM typischerweise die erste Wahl: optimierte Attention-Kernels, In-flight Batching, KV-Cache, Quantisierung bis FP8/FP4/INT4 usw.

Am GB10 ist das besonders attraktiv, weil NVIDIA TensorRT/TensorRT-LLM aktiv für Blackwell pflegt (MHA/FP8-Verbesserungen sind explizit in den Release Notes erwähnt).

Unterschiede: sglang lädt HF-Modelle direkt zur Laufzeit, während TensorRT-LLM normalerweise:
* Modell von Hugging Face laden
* TensorRT Engine bauen (trtllm-build)
* Danach Server starten

Dadurch dauert der erste Start einiges länger, der zweite dauert aber nur halb so lang wie sglang.

    export HF_TOKEN="..."
    
    podman volume create trt-cache
    
    podman rm -f HuggingFaceTB 2>/dev/null || true
    podman run -d --rm \
      --name HuggingFaceTB \
      --device nvidia.com/gpu=all \
      --ipc=host \
      -p 30000:8000 \
      -e HF_TOKEN="$HF_TOKEN" \
      -v trtllm-cache:/root/.cache/huggingface \
      -v /tmp:/tmp \
      nvcr.io/nvidia/tensorrt-llm/release:1.3.0rc7 \
      bash -lc '
        cat > /tmp/extra-llm-api-config.yml <<EOF
    print_iter_log: false
    kv_cache_config:
      dtype: "auto"
      free_gpu_memory_fraction: 0.5
    cuda_graph_config:
      enable_padding: true
    EOF
    
        trtllm-serve HuggingFaceTB/SmolLM2-1.7B-Instruct \
          --backend pytorch \
          --host 0.0.0.0 \
          --port 8000 \
          --max_batch_size 1 \
          --max_num_tokens 2048 \
          --max_seq_len 512 \
          --extra_llm_api_options /tmp/extra-llm-api-config.yml
      '

**Weiter Umgebungen/Modelle**  

    podman volume create trt-cache1
    
    podman rm -f trtllm-smollm2 2>/dev/null || true
    podman run -it --rm \
      --name trtllm-smollm2 \
      --device nvidia.com/gpu=all \
      --ipc=host \
      -p 30001:8000 \
      -e HF_TOKEN="$HF_TOKEN" \
      -v trtllm-cache1:/root/.cache/huggingface \
      -v /tmp:/tmp \
      nvcr.io/nvidia/tensorrt-llm/release:1.3.0rc7 \
      bash -lc '
        cat > /tmp/extra-llm-api-config.yml <<EOF
    print_iter_log: false
    kv_cache_config:
      dtype: "auto"
      free_gpu_memory_fraction: 0.5
    cuda_graph_config:
      enable_padding: true
    EOF
    
        trtllm-serve HuggingFaceTB/SmolLM2-1.7B-Instruct \
          --backend pytorch \
          --host 0.0.0.0 \
          --port 8000 \
          --max_batch_size 1 \
          --max_num_tokens 2048 \
          --max_seq_len 512 \
          --extra_llm_api_options /tmp/extra-llm-api-config.yml
      '

etc.  

Funktionstest  
  
    curl -X POST http://localhost:30001/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d '{
            "model": "HuggingFaceTB/SmolLM2-1.7B-Instruct",
            "messages":[{"role": "system", "content": "You are a helpful assistant."},
                        {"role": "user", "content": "Where is New York? Tell me in a single sentence."}],
            "max_tokens": 32,
            "temperature": 0
        }'    

**Links**:
* [Install and use TensorRT-LLM on DGX Spark](https://build.nvidia.com/spark/trt-llm)
