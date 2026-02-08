ARG VARIANT="noble"
FROM buildpack-deps:${VARIANT}-curl

LABEL dev.containers.features="common"

ARG VARIANT
RUN if [ "$VARIANT" = "noble" ]; then \
        if id "ubuntu" &>/dev/null; then \
            echo "Deleting user 'ubuntu'  for $VARIANT" && userdel -f -r ubuntu || echo "Failed to delete ubuntu user for $VARIANT"; \  
        else \
            echo "User 'ubuntu' does not exist for $VARIANT"; \ 
        fi; \
    fi

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>

# Local fix for issue with timezone data at 'buildpack-deps'. Ref# https://github.com/devcontainers/images/issues/1709
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y reinstall --no-install-recommends tzdata \
												    python3 \
												    python3-venv \
												    python3-pip \
												    curl \
												    jq \
												    git \
												    uuid-runtime \
												    openssh-client \
												    ca-certificates \    
    && rm -rf /var/lib/apt/lists/*

# -------------------------
# Jupyter Base
# -------------------------
RUN python3 -m venv /opt/jupyter \
 && /opt/jupyter/bin/pip install --upgrade pip \
 && /opt/jupyter/bin/pip install jupyterlab ipykernel \
 && /opt/jupyter/bin/python -m ipykernel install \
      --sys-prefix --name=jupyter --display-name="Python (jupyter)"

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

