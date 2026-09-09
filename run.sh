#!/usr/bin/env bash
set -u
WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_ROOT="${COMFYUI_ROOT:-/opt/ComfyUI}"

mkdir -p \
  "$WORKSPACE/models/checkpoints" \
  "$WORKSPACE/models/diffusion_models" \
  "$WORKSPACE/models/vae" \
  "$WORKSPACE/models/loras" \
  "$WORKSPACE/models/text_encoders" \
  "$WORKSPACE/models/text_cond" \
  "$WORKSPACE/input" "$WORKSPACE/output" "$WORKSPACE/temp" \
  "$WORKSPACE/user" "$WORKSPACE/logs"

for name in models input output temp user; do
  if [ -e "$COMFYUI_ROOT/$name" ] && [ ! -L "$COMFYUI_ROOT/$name" ]; then
    rm -rf "$COMFYUI_ROOT/$name"
  fi
  ln -sfn "$WORKSPACE/$name" "$COMFYUI_ROOT/$name"
done

{
  echo "=== MINERVA COMFYUI BASE v1 ==="
  date -Is
  cd "$COMFYUI_ROOT"
  echo
  echo "=== COMFYUI ==="
  git describe --tags --always 2>/dev/null || true
  git rev-parse HEAD 2>/dev/null || true
  echo
  echo "=== PYTHON/TORCH ==="
  python --version
  python - <<'PY'
import torch
print("torch:", torch.__version__)
print("torch cuda:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
PY
  echo
  echo "=== REQUIRED CORE ==="
  test -f "$COMFYUI_ROOT/comfy_extras/nodes_sparse_attention.py" \
    && echo "BlockSparseAttention: FOUND" \
    || echo "BlockSparseAttention: MISSING"
  grep -Rqs "ModelAttentionBackend" "$COMFYUI_ROOT" --include="*.py" \
    && echo "ModelAttentionBackend: FOUND" \
    || echo "ModelAttentionBackend: MISSING"
} | tee "$WORKSPACE/logs/minerva_startup.log"

if [ "${ENABLE_JUPYTER:-1}" = "1" ]; then
  ARGS=(--allow-root --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.root_dir="$WORKSPACE")
  if [ -n "${JUPYTER_TOKEN:-}" ]; then
    ARGS+=(--ServerApp.token="$JUPYTER_TOKEN")
  else
    ARGS+=(--ServerApp.token="" --ServerApp.password="")
  fi
  nohup jupyter lab "${ARGS[@]}" > "$WORKSPACE/logs/jupyter.log" 2>&1 &
fi

cd "$COMFYUI_ROOT"
exec python main.py --listen 0.0.0.0 --port 8188 --enable-manager \
  2>&1 | tee -a "$WORKSPACE/logs/comfyui.log"
