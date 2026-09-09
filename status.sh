#!/usr/bin/env bash
set -u
echo "=== GPU ==="
nvidia-smi || true
echo
echo "=== COMFYUI ==="
cd /opt/ComfyUI
git describe --tags --always 2>/dev/null || true
git log -1 --oneline 2>/dev/null || true
echo
echo "=== REQUIRED CORE ==="
test -f comfy_extras/nodes_sparse_attention.py \
  && echo "BlockSparseAttention: FOUND" \
  || echo "BlockSparseAttention: MISSING"
grep -Rqs "ModelAttentionBackend" . --include="*.py" \
  && echo "ModelAttentionBackend: FOUND" \
  || echo "ModelAttentionBackend: MISSING"
echo
echo "=== PORTS ==="
python - <<'PY'
import socket
for p in (8188, 8888):
    s = socket.socket()
    s.settimeout(.5)
    try:
        ok = s.connect_ex(("127.0.0.1", p)) == 0
        print(f"{p}: {'OPEN' if ok else 'CLOSED'}")
    finally:
        s.close()
PY
