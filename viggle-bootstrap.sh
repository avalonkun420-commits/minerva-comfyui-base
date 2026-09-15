#!/usr/bin/env bash
set -Eeuo pipefail

echo "=================================================="
echo " MINERVA RunPod Viggle Bootstrap"
echo "=================================================="

ROOT="/workspace/runpod-slim"
COMFY="$ROOT/ComfyUI"
NODES="$COMFY/custom_nodes"
MODELS="$COMFY/models"

mkdir -p \
  "$NODES" \
  "$MODELS/diffusion_models" \
  "$MODELS/loras" \
  "$MODELS/text_cond" \
  "$MODELS/vae" \
  "$COMFY/user/default/workflows"

# --------------------------------------------------
# 1. Viggle custom node
# --------------------------------------------------

VIGGLE_NODE="$NODES/ComfyUI-Viggle-Animate-H3"

if [ -d "$VIGGLE_NODE/.git" ]; then
    echo "[Viggle] Updating node..."
    git -C "$VIGGLE_NODE" pull --ff-only || true
else
    echo "[Viggle] Installing node..."
    git clone --depth=1 \
      https://github.com/Saganaki22/ComfyUI-Viggle-Animate-H3.git \
      "$VIGGLE_NODE"
fi

# KJNodes is already included in the official RunPod ComfyUI image.

# --------------------------------------------------
# 2. Hugging Face
# --------------------------------------------------

# Prevent pip from accidentally replacing the CUDA/PyTorch stack
if [ -f /opt/comfyui-runtime-constraints.txt ]; then
    export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
fi

python3.12 -m pip install -q -U huggingface_hub

# Xet automatically handles large-file downloads.
# HP mode only when RAM >= 64GB.
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

if [ "$RAM_GB" -ge 64 ]; then
    export HF_XET_HIGH_PERFORMANCE=1
    echo "[HF] Xet High Performance enabled (${RAM_GB}GB RAM)"
else
    unset HF_XET_HIGH_PERFORMANCE || true
    echo "[HF] Adaptive Xet mode (${RAM_GB}GB RAM)"
fi

# --------------------------------------------------
# 3. Select Viggle model
# --------------------------------------------------

VIGGLE_MODEL="${VIGGLE_MODEL:-pruned}"

case "$VIGGLE_MODEL" in

  pruned)
    DIFFUSION_FILES=(
      "diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors"
    )
    ;;

  full)
    DIFFUSION_FILES=(
      "diffusion_models/minimax_h3_ref2va_viggle_int8_convrot.safetensors"
    )
    ;;

  both)
    DIFFUSION_FILES=(
      "diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors"
      "diffusion_models/minimax_h3_ref2va_viggle_int8_convrot.safetensors"
    )
    ;;

  *)
    echo "Unknown VIGGLE_MODEL=$VIGGLE_MODEL"
    exit 1
    ;;
esac

echo "[Viggle] Model mode: $VIGGLE_MODEL"

# --------------------------------------------------
# 4. Download Viggle
# --------------------------------------------------

hf download drbaph/Viggle-Animate-ComfyUI \
  "${DIFFUSION_FILES[@]}" \
  loras/viggle_animate_dmd_lora_r64.safetensors \
  text_cond/fixed_embed_fwd_anyframe.safetensors \
  --local-dir "$MODELS"

# --------------------------------------------------
# 5. VAE
# --------------------------------------------------

hf download Kijai/MiniMax-H3-experimental \
  minimax_h3_video_vae_int8_convrot.safetensors \
  --local-dir "$MODELS/vae"

# --------------------------------------------------
# 6. Restore included Viggle workflows
# --------------------------------------------------

if [ -d "$VIGGLE_NODE/example_workflows" ]; then
    mkdir -p "$COMFY/user/default/workflows/Viggle"
    cp -f "$VIGGLE_NODE"/example_workflows/*.json \
      "$COMFY/user/default/workflows/Viggle/" 2>/dev/null || true
fi

# --------------------------------------------------
# 7. Verification
# --------------------------------------------------

echo
echo "Installed Viggle files:"
find "$MODELS" -type f \
  \( -iname '*viggle*' -o \
     -iname '*fixed_embed*' -o \
     -iname '*minimax_h3_video_vae*' \) \
  -printf '%p\n'

echo
echo "=================================================="
echo " Bootstrap finished."
echo " Starting official RunPod ComfyUI..."
echo "=================================================="
