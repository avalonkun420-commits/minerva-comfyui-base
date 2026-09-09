#!/usr/bin/env bash
set -u
COMFY="/workspace/runpod-slim/ComfyUI"

echo "=== GPU ==="
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true

echo
echo "=== TORCH ==="
python3.12 - <<'PY'
import torch
print("torch:", torch.__version__)
print("torch CUDA:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
PY

echo
echo "=== COMFYUI ==="
if [ -d "$COMFY/.git" ]; then
  git -C "$COMFY" log -1 --oneline
  git -C "$COMFY" rev-parse HEAD
else
  echo "ComfyUI git checkout: MISSING"
fi

echo
echo "=== FULL ATTENTION ==="
test -f "$COMFY/comfy_extras/nodes_sparse_attention.py" \
  && echo "BlockSparseAttention: FOUND" \
  || echo "BlockSparseAttention: MISSING"

grep -Rqs "ModelAttentionBackend" "$COMFY/comfy_extras" --include="*.py" \
  && echo "ModelAttentionBackend: FOUND" \
  || echo "ModelAttentionBackend: MISSING"

python3.12 - <<'PY'
try:
    import comfy_kitchen
    print("comfy_kitchen: IMPORT OK")
    import comfy_kitchen.backends.cuda._C
    print("comfy_kitchen CUDA backend: IMPORT OK")
except Exception as e:
    print("comfy_kitchen CUDA backend: FAIL")
    print(repr(e))
PY

echo
echo "=== VIGGLE FILES ==="
for f in \
  "$COMFY/models/diffusion_models/minimax_h3_ref2va_viggle_pruned_int8_convrot.safetensors" \
  "$COMFY/models/loras/viggle_animate_dmd_lora_r64.safetensors" \
  "$COMFY/models/text_cond/fixed_embed_fwd_anyframe.safetensors" \
  "$COMFY/models/vae/minimax_h3_video_vae_int8_convrot.safetensors" \
  "$COMFY/models/vae/minimax_h3_video_vae_fp16.safetensors"
do
  if [ -s "$f" ]; then
    echo "OK   $(du -h "$f" | cut -f1)  $f"
  else
    echo "MISS $f"
  fi
done

echo
echo "=== PORT 8188 ==="
python3.12 - <<'PY'
import socket
s = socket.socket()
s.settimeout(.5)
print("8188:", "OPEN" if s.connect_ex(("127.0.0.1", 8188)) == 0 else "CLOSED")
s.close()
PY
