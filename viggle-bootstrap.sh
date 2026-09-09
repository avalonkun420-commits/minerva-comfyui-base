#!/usr/bin/env bash
set -Eeuo pipefail

COMFY="/workspace/runpod-slim/ComfyUI"
NODES="$COMFY/custom_nodes"
WORKFLOWS="$COMFY/user/default/workflows"
LOG="/workspace/viggle_bootstrap.log"

exec > >(tee -a "$LOG") 2>&1

trap 'echo; echo "============================================================"; echo "[MINERVA] BOOTSTRAP FAILED at line $LINENO"; echo "Log: $LOG"; echo "============================================================"' ERR

echo "============================================================"
echo " MINERVA VIGGLE BOOTSTRAP v1"
echo " $(date -Is)"
echo "============================================================"

echo
echo "[0/8] GPU / CUDA sanity check"

DRIVER_MAJOR="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | cut -d. -f1)"
GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)"

echo "GPU: $GPU_NAME"
echo "Driver major: $DRIVER_MAJOR"

if [ "${DRIVER_MAJOR:-0}" -lt 580 ]; then
  echo "[FATAL] NVIDIA driver must be 580+ for this CUDA 13.0 setup."
  exit 20
fi

python3.12 - <<'PY'
import sys, torch
print("torch:", torch.__version__)
print("torch CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if not torch.cuda.is_available():
    raise SystemExit("CUDA is unavailable")
print("GPU:", torch.cuda.get_device_name(0))
if not str(torch.version.cuda).startswith("13."):
    print("[WARN] This bootstrap was validated on CUDA 13.x.")
PY

echo
echo "[1/8] Stop bundled / old ComfyUI"

pkill -f "/workspace/runpod-slim/ComfyUI/main.py" 2>/dev/null || true
pkill -f "python main.py --listen 0.0.0.0 --port 8188" 2>/dev/null || true
pkill -f "python3.12 main.py --listen 0.0.0.0 --port 8188" 2>/dev/null || true
sleep 3

echo
echo "[2/8] Force ComfyUI to current master"

cd "$COMFY"
git fetch origin master
git checkout -f master
git reset --hard origin/master

echo "ComfyUI:"
git log -1 --oneline

echo
echo "[3/8] Install current ComfyUI dependencies"

if [ -f /opt/comfyui-runtime-constraints.txt ]; then
  python3.12 -m pip install -r "$COMFY/requirements.txt" \
    -c /opt/comfyui-runtime-constraints.txt
else
  python3.12 -m pip install -r "$COMFY/requirements.txt"
fi

echo
echo "[4/8] Install / update Viggle nodes"

mkdir -p "$NODES"

update_repo() {
  local url="$1"
  local dir="$2"
  local branch="${3:-}"

  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch --prune origin
    if [ -n "$branch" ]; then
      git -C "$dir" checkout -B "$branch" "origin/$branch"
    else
      local default_branch
      default_branch="$(git -C "$dir" remote show origin | sed -n '/HEAD branch/s/.*: //p')"
      git -C "$dir" checkout -B "$default_branch" "origin/$default_branch"
    fi
  else
    if [ -n "$branch" ]; then
      git clone --branch "$branch" "$url" "$dir"
    else
      git clone "$url" "$dir"
    fi
  fi
}

update_repo \
  "https://github.com/Saganaki22/ComfyUI-Viggle-Animate-H3.git" \
  "$NODES/ComfyUI-Viggle-Animate-H3" \
  "main"

update_repo \
  "https://github.com/kijai/ComfyUI-KJNodes.git" \
  "$NODES/ComfyUI-KJNodes" \
  "main"

update_repo \
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
  "$NODES/ComfyUI-VideoHelperSuite"

update_repo \
  "https://github.com/jamesWalker55/comfyui-various.git" \
  "$NODES/comfyui-various"

for D in \
  "$NODES/ComfyUI-Viggle-Animate-H3" \
  "$NODES/ComfyUI-KJNodes" \
  "$NODES/ComfyUI-VideoHelperSuite" \
  "$NODES/comfyui-various"
do
  if [ -f "$D/requirements.txt" ]; then
    echo "Installing requirements: $D"
    if [ -f /opt/comfyui-runtime-constraints.txt ]; then
      python3.12 -m pip install -r "$D/requirements.txt" \
        -c /opt/comfyui-runtime-constraints.txt
    else
      python3.12 -m pip install -r "$D/requirements.txt"
    fi
  fi
done

echo
echo "[5/8] Install Hugging Face/Xet + Comfy Kitchen"

python3.12 -m pip install -U \
  huggingface_hub \
  hf_xet \
  "comfy-kitchen==0.2.33"

RAM_GB="$(awk '/MemTotal/ {printf "%d",$2/1024/1024}' /proc/meminfo)"
if [ "$RAM_GB" -ge 64 ]; then
  export HF_XET_HIGH_PERFORMANCE=1
  echo "HF_XET_HIGH_PERFORMANCE=1"
fi

echo
echo "[6/8] Download Viggle models directly into ComfyUI/models"

mkdir -p \
  "$COMFY/models/diffusion_models" \
  "$COMFY/models/loras" \
  "$COMFY/models/text_cond" \
  "$COMFY/models/vae"

hf download drbaph/Viggle-Animate-ComfyUI \
  diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors \
  --local-dir "$COMFY/models"

hf download drbaph/Viggle-Animate-ComfyUI \
  loras/viggle_animate_dmd_lora_r64.safetensors \
  --local-dir "$COMFY/models"

hf download drbaph/Viggle-Animate-ComfyUI \
  text_cond/fixed_embed_fwd_anyframe.safetensors \
  --local-dir "$COMFY/models"

hf download Comfy-Org/MiniMax-H3 \
  vae/minimax_h3_video_vae_fp16.safetensors \
  --local-dir "$COMFY/models"

echo
echo "[7/8] Install official Single Shot workflow"

mkdir -p "$WORKFLOWS"

cp -f \
  "$NODES/ComfyUI-Viggle-Animate-H3/example_workflows/viggle-animate-h3_workflow-v1.2.0.json" \
  "$WORKFLOWS/MINERVA_VIGGLE_5090_SINGLESHOT.json"

# First test uses FP16 VAE to avoid introducing the INT8-VAE black-output variable.
sed -i \
  's/minimax_h3_video_vae_int8_convrot\.safetensors/minimax_h3_video_vae_fp16.safetensors/g' \
  "$WORKFLOWS/MINERVA_VIGGLE_5090_SINGLESHOT.json"

echo
echo "[8/8] Verify + start latest ComfyUI only"

test -f "$COMFY/comfy_extras/nodes_sparse_attention.py"
grep -Rqs "ModelAttentionBackend" "$COMFY/comfy_extras"

for F in \
  "$COMFY/models/diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors" \
  "$COMFY/models/loras/viggle_animate_dmd_lora_r64.safetensors" \
  "$COMFY/models/text_cond/fixed_embed_fwd_anyframe.safetensors" \
  "$COMFY/models/vae/minimax_h3_video_vae_fp16.safetensors"
do
  test -s "$F"
  ls -lh "$F"
done

# Kill anything that may have appeared on 8188 during provisioning.
pkill -f "/workspace/runpod-slim/ComfyUI/main.py" 2>/dev/null || true
pkill -f "python main.py --listen 0.0.0.0 --port 8188" 2>/dev/null || true
pkill -f "python3.12 main.py --listen 0.0.0.0 --port 8188" 2>/dev/null || true
sleep 2

cd "$COMFY"

nohup /usr/bin/python3.12 "$COMFY/main.py" \
  --listen 0.0.0.0 \
  --port 8188 \
  --enable-cors-header \
  > /workspace/viggle_comfyui.log 2>&1 &

NEW_PID=$!
echo "$NEW_PID" > /workspace/viggle_comfyui.pid

echo "Started latest ComfyUI PID: $NEW_PID"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8188/system_stats >/tmp/minerva_system_stats.json 2>/dev/null; then
    break
  fi
  sleep 1
done

if ! kill -0 "$NEW_PID" 2>/dev/null; then
  echo "[FATAL] Latest ComfyUI exited."
  tail -n 120 /workspace/viggle_comfyui.log || true
  exit 30
fi

echo
echo "=== ComfyUI startup verification ==="
grep -E \
  "ComfyUI startup time|ComfyUI Path|pytorch version|Device:|Found comfy_kitchen backend cuda|Using .* attention" \
  /workspace/viggle_comfyui.log | tail -n 30 || true

if grep -q "Found comfy_kitchen backend cuda: {'available': True" /workspace/viggle_comfyui.log; then
  echo "Comfy Kitchen CUDA backend: OK"
else
  echo "[WARN] Could not confirm Comfy Kitchen CUDA backend from startup log."
fi

echo
echo "Workflow:"
echo "$WORKFLOWS/MINERVA_VIGGLE_5090_SINGLESHOT.json"

echo
echo "============================================================"
echo " MINERVA VIGGLE READY"
echo " Open RunPod HTTP Service :8188"
echo " Then hard-refresh the browser (Ctrl+Shift+R)."
echo " Log: /workspace/viggle_bootstrap.log"
echo " ComfyUI log: /workspace/viggle_comfyui.log"
echo "============================================================"
