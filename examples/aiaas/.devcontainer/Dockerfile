FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-pip \
    curl \
    jq \
    git \
    uuid-runtime \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# -------------------------
# Jupyter Base
# -------------------------
RUN python3 -m venv /opt/jupyter \
 && /opt/jupyter/bin/pip install --upgrade pip \
 && /opt/jupyter/bin/pip install jupyterlab ipykernel

# -------------------------
# AI Kernel
# -------------------------
RUN python3 -m venv /opt/ai \
 && /opt/ai/bin/pip install --upgrade pip \
 && /opt/ai/bin/pip install openai ipykernel nbconvert \
 && /opt/ai/bin/python -m ipykernel install \
      --sys-prefix --name=ai --display-name="Python (ai)"

# -------------------------
# RAG Kernel
# -------------------------
RUN python3 -m venv /opt/rag \
 && /opt/rag/bin/pip install --upgrade pip \
 && /opt/rag/bin/pip install ipykernel chromadb pypdf requests tqdm \
 && /opt/rag/bin/python -m ipykernel install \
      --sys-prefix --name=rag --display-name="Python (rag)"

# -------------------------
# MCP Kernel
# -------------------------
RUN python3 -m venv /opt/mcp \
 && /opt/mcp/bin/pip install --upgrade pip \
 && /opt/mcp/bin/pip install ipykernel mcp requests openai \
 && /opt/mcp/bin/python -m ipykernel install \
      --sys-prefix --name=mcp --display-name="Python (mcp)"

