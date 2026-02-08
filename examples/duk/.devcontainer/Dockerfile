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
# kind && kubectl && helm
# -------------------------
RUN curl -Lo kind "https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64" \
    && chmod +x kind \
    && mv kind /usr/local/bin/
    
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash        
        
# Mount for docker-in-docker 
VOLUME [ "/var/lib/docker" ]    
    