# MINERVA COMFYUI BASE v1
FROM nvidia/cuda:13.0.3-base-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG COMFYUI_REF=master

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    COMFYUI_ROOT=/opt/ComfyUI

RUN apt-get update && apt-get install -y --no-install-recommends \
      python3.12 python3.12-venv python3-pip \
      git git-lfs ffmpeg curl wget ca-certificates \
      build-essential pkg-config libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN python3.12 -m venv /opt/venv \
    && /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel

RUN /opt/venv/bin/pip install torch torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cu130

RUN git clone --depth 1 --branch "${COMFYUI_REF}" \
      https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI \
    && /opt/venv/bin/pip install -r /opt/ComfyUI/requirements.txt \
    && /opt/venv/bin/pip install -r /opt/ComfyUI/manager_requirements.txt \
    && /opt/venv/bin/pip install jupyterlab

RUN test -f /opt/ComfyUI/comfy_extras/nodes_sparse_attention.py \
    && grep -Rqs "ModelAttentionBackend" /opt/ComfyUI --include="*.py"

COPY run.sh /opt/minerva/run.sh
COPY status.sh /opt/minerva/status.sh
RUN chmod +x /opt/minerva/run.sh /opt/minerva/status.sh

WORKDIR /opt/ComfyUI
EXPOSE 8188 8888
CMD ["/opt/minerva/run.sh"]
