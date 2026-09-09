# MINERVA COMFYUI BASE v1 - FULL ATTENTION READY
FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04

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
      build-essential pkg-config \
      cmake ninja-build \
      libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN python3.12 -m venv /opt/venv \
    && /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel

# CUDA 13 PyTorch
RUN /opt/venv/bin/pip install \
      torch torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cu130

# ComfyUI current master (BlockSparseAttention が必要)
RUN git clone --depth 1 --branch "${COMFYUI_REF}" \
      https://github.com/Comfy-Org/ComfyUI.git /opt/ComfyUI

RUN /opt/venv/bin/pip install -r /opt/ComfyUI/requirements.txt \
    && /opt/venv/bin/pip install -r /opt/ComfyUI/manager_requirements.txt \
    && /opt/venv/bin/pip install jupyterlab

# comfy-kitchen (Comfy Kitchen attention 用)
RUN /opt/venv/bin/pip install "git+https://github.com/Comfy-Org/comfy-kitchen.git"

# Build-time sanity check
RUN /opt/venv/bin/python - <<'PY'
from pathlib import Path
import importlib

assert Path("/opt/ComfyUI/comfy_extras/nodes_sparse_attention.py").exists(), "BlockSparseAttention source missing"

text = Path("/opt/ComfyUI/comfy_extras/nodes_model_advanced.py").read_text(encoding="utf-8")
assert "class ModelAttentionBackend" in text, "ModelAttentionBackend missing"

import comfy_kitchen
import comfy_kitchen.backends.cuda._C

print("OK: BlockSparseAttention source found")
print("OK: ModelAttentionBackend found")
print("OK: comfy_kitchen CUDA extension import success")
PY

COPY run.sh /opt/minerva/run.sh
COPY status.sh /opt/minerva/status.sh
RUN chmod +x /opt/minerva/run.sh /opt/minerva/status.sh

WORKDIR /opt/ComfyUI

EXPOSE 8188 8888

CMD ["/opt/minerva/run.sh"]
