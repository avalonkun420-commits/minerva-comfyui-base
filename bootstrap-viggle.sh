#!/usr/bin/env bash
set -Eeuo pipefail

echo "=================================================="
echo " MINERVA RunPod / ComfyUI / Viggle Bootstrap"
echo "=================================================="

BASE="/workspace/runpod-slim"
COMFY="$BASE/ComfyUI"
NODES="$COMFY/custom_nodes"
MODELS="$COMFY/models"

VIGGLE_NODE="$NODES/ComfyUI-Viggle-Animate-H3"
VHS_NODE="$NODES/ComfyUI-VideoHelperSuite"

# --------------------------------------------------
# 1. Initialize official RunPod ComfyUI FIRST
# --------------------------------------------------

mkdir -p "$BASE"

if [ ! -f "$COMFY/main.py" ]; then
    echo "[1/7] Initializing official baked ComfyUI..."
    mkdir -p "$COMFY"
    rsync -a /opt/comfyui-baked/ "$COMFY/"
else
    echo "[1/7] Existing ComfyUI found - keeping it."
fi

mkdir -p \
    "$NODES" \
    "$MODELS/diffusion_models" \
    "$MODELS/loras" \
    "$MODELS/text_cond" \
    "$MODELS/vae" \
    "$COMFY/user/default/workflows/Viggle"

# Protect RunPod's CUDA / PyTorch stack
if [ -f /opt/comfyui-runtime-constraints.txt ]; then
    export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt
fi

# --------------------------------------------------
# 2. Custom nodes
# --------------------------------------------------

clone_or_update() {
    URL="$1"
    DIR="$2"

    if [ -d "$DIR/.git" ]; then
        echo "Updating: $(basename "$DIR")"
        git -C "$DIR" pull --ff-only || true
    else
        echo "Installing: $(basename "$DIR")"
        git clone --depth=1 "$URL" "$DIR"
    fi
}

echo "[2/7] Installing/updating Viggle nodes..."

clone_or_update \
    "https://github.com/Saganaki22/ComfyUI-Viggle-Animate-H3.git" \
    "$VIGGLE_NODE"

# KJNodes is already baked into the official RunPod ComfyUI image.

clone_or_update \
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
    "$VHS_NODE"

# VHS runtime dependencies
if [ -f "$VHS_NODE/requirements.txt" ]; then
    python3.12 -m pip install -q -r "$VHS_NODE/requirements.txt"
fi

# --------------------------------------------------
# 3. Hugging Face / Xet
# --------------------------------------------------

echo "[3/7] Preparing Hugging Face downloader..."

python3.12 -m pip install -q -U \
    huggingface_hub \
    hf_xet

RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

if [ "$RAM_GB" -ge 64 ]; then
    export HF_XET_HIGH_PERFORMANCE=1
    echo "HF Xet high-performance mode: ON (${RAM_GB}GB RAM)"
else
    unset HF_XET_HIGH_PERFORMANCE 2>/dev/null || true
    echo "HF Xet adaptive mode (${RAM_GB}GB RAM)"
fi

if [ -n "${HF_TOKEN:-}" ]; then
    echo "HF_TOKEN detected."
else
    echo "WARNING: HF_TOKEN is not set. Public downloads still work, but may be slower."
fi

# --------------------------------------------------
# 4. Select Viggle transformer
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
        echo "ERROR: Unknown VIGGLE_MODEL=$VIGGLE_MODEL"
        exit 1
        ;;
esac

echo "[4/7] Viggle model mode: $VIGGLE_MODEL"

# --------------------------------------------------
# 5. Download Viggle weights
# --------------------------------------------------

echo "[5/7] Downloading Viggle model files..."

hf download drbaph/Viggle-Animate-ComfyUI \
    "${DIFFUSION_FILES[@]}" \
    loras/viggle_animate_dmd_lora_r64.safetensors \
    text_cond/fixed_embed_fwd_anyframe.safetensors \
    --local-dir "$MODELS"

# --------------------------------------------------
# 6. Download H3 VAE
# --------------------------------------------------

echo "[6/7] Downloading MiniMax H3 VAE..."

hf download Kijai/MiniMax-H3-experimental \
    minimax_h3_video_vae_int8_convrot.safetensors \
    --local-dir "$MODELS/vae"

# --------------------------------------------------
# 7. Install example workflows
# --------------------------------------------------

echo "[7/7] Installing Viggle workflows..."

if [ -d "$VIGGLE_NODE/example_workflows" ]; then
    cp -f \
        "$VIGGLE_NODE"/example_workflows/*.json \
        "$COMFY/user/default/workflows/Viggle/" \
        2>/dev/null || true
fi

echo
echo "Installed Viggle files:"
find "$MODELS" -type f \
    \( \
        -iname '*viggle*' \
        -o -iname '*fixed_embed*' \
        -o -iname '*minimax_h3_video_vae*' \
    \) \
    -printf '%p\n'

echo
echo "=================================================="
echo " MINERVA bootstrap completed successfully"
echo "=================================================="
