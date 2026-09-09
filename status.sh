#!/usr/bin/env bash
set -u

echo "=== GPU ==="
nvidia-smi || true

echo
echo "=== COMFYUI ==="
cd /opt/ComfyUI
git branch --show-current 2>/dev/null || true
git log -1 --oneline 2>/dev/null || true

echo
echo "=== REQUIRED CORE ==="
test -f comfy_extras/nodes_sparse_attention.py \
  && echo "BlockSparseAttention: FOUND" \
  || echo "BlockSparseAttention: MISSING"

grep -qs "class ModelAttentionBackend" comfy_extras/nodes_model_advanced.py \
  && echo "ModelAttentionBackend: FOUND" \
  || echo "ModelAttentionBackend: MISSING"

echo
echo "=== COMFY KITCHEN ==="
python - <<'PY'
ok = True
try:
    import comfy_kitchen
    print("comfy_kitchen: IMPORT OK")
except Exception as e:
    ok = False
    print("comfy_kitchen: IMPORT FAIL")
    print(e)

try:
    import comfy_kitchen.backends.cuda._C as ck
    print("comfy_kitchen CUDA backend: IMPORT OK")
except Exception as e:
    ok = False
    print("comfy_kitchen CUDA backend: IMPORT FAIL")
    print(e)

raise SystemExit(0 if ok else 1)
PY

echo
echo "=== PORTS ==="
python - <<'PY'
import socket
for p in (8188, 8888):
    s = socket.socket()
    s.settimeout(0.5)
    try:
        ok = s.connect_ex(("127.0.0.1", p)) == 0
        print(f"{p}: {'OPEN' if ok else 'CLOSED'}")
    finally:
        s.close()
PY
