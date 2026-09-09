#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/workspace/runpod-slim"
COMFY="$ROOT/ComfyUI"
LOG_DIR="$ROOT/minerva_logs"
WORKFLOW_DIR="$ROOT/MINERVA_WORKFLOWS"
PIP_CONSTRAINT_FILE="/opt/comfyui-runtime-constraints.txt"

mkdir -p "$ROOT" "$LOG_DIR" "$WORKFLOW_DIR"
LOG="$LOG_DIR/bootstrap_$(date +%Y%m%d_%H%M%S).log"

exec > >(tee -a "$LOG") 2>&1

on_error() {
  rc=$?
  echo
  echo "============================================================"
  echo "[MINERVA] BOOTSTRAP FAILED (exit=$rc)"
  echo "[MINERVA] Log: $LOG"
  echo "[MINERVA] Container kept alive for debugging."
  echo "============================================================"
  trap - ERR
  sleep infinity
}
trap on_error ERR

echo "============================================================"
echo " MINERVA VIGGLE LAB v1 - FAST BOOT"
echo " $(date -Is)"
echo "============================================================"

echo
echo "[1/8] GPU / base runtime"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
python3.12 - <<'PY'
import torch
print("torch:", torch.__version__)
print("torch CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
PY

echo
echo "[2/8] Current ComfyUI master"
if [ -d "$COMFY/.git" ]; then
  git -C "$COMFY" fetch --depth 1 origin master
  git -C "$COMFY" reset --hard origin/master
else
  rm -rf "$COMFY"
  git clone --depth 1 --branch master https://github.com/Comfy-Org/ComfyUI.git "$COMFY"
fi

echo "[MINERVA] ComfyUI commit: $(git -C "$COMFY" rev-parse HEAD)"
git -C "$COMFY" log -1 --oneline

cat > "$ROOT/comfyui_args.txt" <<'EOF'
--enable-manager
EOF

echo
echo "[3/8] Update ComfyUI runtime dependencies"
export PIP_CONSTRAINT="$PIP_CONSTRAINT_FILE"
python3.12 -m pip install -q --upgrade \
  --constraint "$PIP_CONSTRAINT_FILE" \
  -r "$COMFY/requirements.txt"

if [ -f "$COMFY/manager_requirements.txt" ]; then
  python3.12 -m pip install -q --upgrade \
    --constraint "$PIP_CONSTRAINT_FILE" \
    -r "$COMFY/manager_requirements.txt"
fi

python3.12 -m pip install -q --upgrade \
  --only-binary=comfy-kitchen \
  "comfy-kitchen==0.2.33"

echo
echo "[4/8] Viggle + required custom nodes"

clone_or_update() {
  local url="$1"
  local dir="$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only
  else
    rm -rf "$dir"
    git clone --depth 1 "$url" "$dir"
  fi
}

mkdir -p "$COMFY/custom_nodes"

clone_or_update \
  https://github.com/Saganaki22/ComfyUI-Viggle-Animate-H3.git \
  "$COMFY/custom_nodes/ComfyUI-Viggle-Animate-H3"

clone_or_update \
  https://github.com/kijai/ComfyUI-KJNodes.git \
  "$COMFY/custom_nodes/ComfyUI-KJNodes"

clone_or_update \
  https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
  "$COMFY/custom_nodes/ComfyUI-VideoHelperSuite"

clone_or_update \
  https://github.com/jamesWalker55/comfyui-various.git \
  "$COMFY/custom_nodes/comfyui-various"

for req in "$COMFY"/custom_nodes/*/requirements.txt; do
  [ -f "$req" ] || continue
  echo "[MINERVA] pip requirements: $req"
  python3.12 -m pip install -q --upgrade \
    --constraint "$PIP_CONSTRAINT_FILE" \
    -r "$req"
done

python3.12 -m pip install -q --upgrade "huggingface_hub[cli]" hf_xet

MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "${MEM_KB:-0}" -ge 67108864 ]; then
  export HF_XET_HIGH_PERFORMANCE=1
  echo "[MINERVA] HF_XET_HIGH_PERFORMANCE=1"
else
  export HF_XET_HIGH_PERFORMANCE=0
  echo "[MINERVA] HF_XET_HIGH_PERFORMANCE=0"
fi
export HF_HOME="$ROOT/.cache/huggingface"
export HF_HUB_DOWNLOAD_TIMEOUT=120
mkdir -p "$HF_HOME"

echo
echo "[5/8] Model download (skip existing files)"
mkdir -p \
  "$COMFY/models/diffusion_models" \
  "$COMFY/models/loras" \
  "$COMFY/models/text_cond" \
  "$COMFY/models/vae"

hf_one() {
  local repo="$1"
  local file="$2"
  local local_dir="$3"
  local expected="$local_dir/$file"

  if [ -s "$expected" ]; then
    echo "[SKIP] $expected"
    return 0
  fi

  echo "[DOWNLOAD] $repo :: $file"
  hf download "$repo" "$file" --local-dir "$local_dir"
  test -s "$expected"
}

hf_one \
  "drbaph/Viggle-Animate-ComfyUI" \
  "diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors" \
  "$COMFY/models"

hf_one \
  "drbaph/Viggle-Animate-ComfyUI" \
  "loras/viggle_animate_dmd_lora_r64.safetensors" \
  "$COMFY/models"

hf_one \
  "drbaph/Viggle-Animate-ComfyUI" \
  "text_cond/fixed_embed_fwd_anyframe.safetensors" \
  "$COMFY/models"

hf_one \
  "Kijai/MiniMax-H3-experimental" \
  "minimax_h3_video_vae_int8_convrot.safetensors" \
  "$COMFY/models/vae"

hf_one \
  "Comfy-Org/MiniMax-H3" \
  "vae/minimax_h3_video_vae_fp16.safetensors" \
  "$COMFY/models"

echo
echo "[6/8] Copy current official Viggle workflows"
rm -rf "$WORKFLOW_DIR/Viggle"
mkdir -p "$WORKFLOW_DIR/Viggle"
cp -a "$COMFY/custom_nodes/ComfyUI-Viggle-Animate-H3/example_workflows/." \
      "$WORKFLOW_DIR/Viggle/"

echo
echo "[7/8] Full-attention validation"
test -f "$COMFY/comfy_extras/nodes_sparse_attention.py"
grep -Rqs "ModelAttentionBackend" "$COMFY/comfy_extras" --include="*.py"

python3.12 - <<'PY'
import comfy_kitchen
print("comfy_kitchen:", getattr(comfy_kitchen, "__version__", "installed"))
import comfy_kitchen.backends.cuda._C
print("comfy_kitchen CUDA backend: IMPORT OK")
PY

echo "BlockSparseAttention: FOUND"
echo "ModelAttentionBackend: FOUND"

echo
echo "[8/8] Handing off to RunPod /start.sh"
echo "============================================================"
echo " MINERVA VIGGLE LAB READY"
echo " ComfyUI: 8188"
echo " Workflows: $WORKFLOW_DIR/Viggle"
echo " Log: $LOG"
echo "============================================================"

exec /start.sh
