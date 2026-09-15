#!/usr/bin/env bash
set -Eeuo pipefail

echo "=================================================="
echo " MINERVA RunPod / Latest ComfyUI / Viggle"
echo "=================================================="

BASE="/workspace/runpod-slim"
COMFY="$BASE/ComfyUI"
NODES="$COMFY/custom_nodes"
MODELS="$COMFY/models"
VENV="$COMFY/.venv-minerva"

COMFY_REF="${COMFY_REF:-v0.35.0}"
VIGGLE_MODEL="${VIGGLE_MODEL:-pruned}"

export PIP_CONSTRAINT=/opt/comfyui-runtime-constraints.txt

mkdir -p "$BASE"

# --------------------------------------------------
# 1. Latest stable ComfyUI
# --------------------------------------------------

echo "[1/8] Installing ComfyUI $COMFY_REF"

if [ ! -d "$COMFY/.git" ]; then
    rm -rf "$COMFY"

    git clone \
        --depth=1 \
        --branch "$COMFY_REF" \
        https://github.com/Comfy-Org/ComfyUI.git \
        "$COMFY"
else
    git -C "$COMFY" remote set-url origin \
        https://github.com/Comfy-Org/ComfyUI.git

    git -C "$COMFY" fetch \
        --depth=1 \
        origin "$COMFY_REF"

    git -C "$COMFY" reset --hard FETCH_HEAD
fi

# Disable RunPod baked bundle management
rm -f "$COMFY/.runpod-bundle-version"

echo "ComfyUI:"
git -C "$COMFY" describe --tags --always

# --------------------------------------------------
# 2. Python venv
# --------------------------------------------------

echo "[2/8] Preparing Python environment"

if [ ! -d "$VENV" ]; then
    python3.12 -m venv \
        --system-site-packages \
        "$VENV"
fi

source "$VENV/bin/activate"

python -m ensurepip >/dev/null 2>&1 || true
python -m pip install -q -U pip

echo "Installing current ComfyUI requirements..."

python -m pip install \
    -r "$COMFY/requirements.txt"

# --------------------------------------------------
# 3. Directories
# --------------------------------------------------

mkdir -p \
    "$NODES" \
    "$MODELS/diffusion_models" \
    "$MODELS/loras" \
    "$MODELS/text_cond" \
    "$MODELS/vae" \
    "$COMFY/user/default/workflows/Viggle"

# --------------------------------------------------
# Repo sync helper
# --------------------------------------------------

sync_repo() {
    URL="$1"
    DIR="$2"

    if [ -d "$DIR/.git" ]; then
        echo "Updating $(basename "$DIR")"

        git -C "$DIR" remote set-url origin "$URL"
        git -C "$DIR" fetch --depth=1 origin HEAD
        git -C "$DIR" reset --hard FETCH_HEAD
    else
        rm -rf "$DIR"

        echo "Installing $(basename "$DIR")"
        git clone --depth=1 "$URL" "$DIR"
    fi
}

# --------------------------------------------------
# 4. Custom nodes
# --------------------------------------------------

echo "[3/8] Installing latest custom nodes"

sync_repo \
    "https://github.com/ltdrdata/ComfyUI-Manager.git" \
    "$NODES/ComfyUI-Manager"

sync_repo \
    "https://github.com/kijai/ComfyUI-KJNodes.git" \
    "$NODES/ComfyUI-KJNodes"

sync_repo \
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
    "$NODES/ComfyUI-VideoHelperSuite"

sync_repo \
    "https://github.com/Saganaki22/ComfyUI-Viggle-Animate-H3.git" \
    "$NODES/ComfyUI-Viggle-Animate-H3"

# Install node dependencies
for req in \
    "$NODES/ComfyUI-Manager/requirements.txt" \
    "$NODES/ComfyUI-KJNodes/requirements.txt" \
    "$NODES/ComfyUI-VideoHelperSuite/requirements.txt"
do
    if [ -f "$req" ]; then
        echo "Installing $(dirname "$req") requirements"
        python -m pip install -q -r "$req"
    fi
done

# --------------------------------------------------
# 5. HF
# --------------------------------------------------

echo "[4/8] Preparing Hugging Face"

python -m pip install -q -U \
    huggingface_hub \
    hf_xet

RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

if [ "$RAM_GB" -ge 64 ]; then
    export HF_XET_HIGH_PERFORMANCE=1
    echo "HF Xet HIGH PERFORMANCE (${RAM_GB} GB RAM)"
else
    unset HF_XET_HIGH_PERFORMANCE 2>/dev/null || true
    echo "HF Xet adaptive (${RAM_GB} GB RAM)"
fi

# --------------------------------------------------
# 6. Viggle model selection
# --------------------------------------------------

echo "[5/8] Selecting Viggle model: $VIGGLE_MODEL"

case "$VIGGLE_MODEL" in

    pruned)
        MODEL_FILE="diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors"
        ;;

    full)
        MODEL_FILE="diffusion_models/minimax_h3_ref2va_viggle_int8_convrot.safetensors"
        ;;

    *)
        echo "ERROR: VIGGLE_MODEL must be pruned or full"
        exit 1
        ;;
esac

# --------------------------------------------------
# 7. Models
# --------------------------------------------------

echo "[6/8] Downloading Viggle files"

hf download drbaph/Viggle-Animate-ComfyUI \
    "$MODEL_FILE" \
    loras/viggle_animate_dmd_lora_r64.safetensors \
    text_cond/fixed_embed_fwd_anyframe.safetensors \
    --local-dir "$MODELS"

echo "[7/8] Downloading MiniMax H3 VAE"

hf download Kijai/MiniMax-H3-experimental \
    minimax_h3_video_vae_int8_convrot.safetensors \
    --local-dir "$MODELS/vae"

# --------------------------------------------------
# 8. Workflows
# --------------------------------------------------

echo "[8/8] Installing Viggle workflows"

VIGGLE_NODE="$NODES/ComfyUI-Viggle-Animate-H3"

if [ -d "$VIGGLE_NODE/example_workflows" ]; then
    cp -f \
        "$VIGGLE_NODE"/example_workflows/*.json \
        "$COMFY/user/default/workflows/Viggle/" \
        2>/dev/null || true
fi

echo
echo "=================================================="
echo " Final versions"
echo "=================================================="

echo "ComfyUI:"
git -C "$COMFY" describe --tags --always

echo "Viggle:"
git -C "$VIGGLE_NODE" log -1 --oneline

python - <<'PY'
import torch
print("PyTorch:", torch.__version__)
print("CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name())
PY

echo
echo "=================================================="
echo " Starting ComfyUI directly - NO RunPod /start.sh"
echo "=================================================="

cd "$COMFY"

exec python main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --enable-cors-header
