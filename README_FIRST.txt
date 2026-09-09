MINERVA VIGGLE LAB v1 — THIN WRAPPER

既存の minerva-comfyui-base リポジトリを薄型版へ更新します。

置き換える:
- Dockerfile
- minerva-start.sh
- status.sh
- .github/workflows/build.yml

以前の run.sh は削除推奨。

設計:
- Docker base = runpod/comfyui:1.4.6-cuda13.0
- 自作Docker layer = 起動scriptだけ
- Pod起動後に current ComfyUI master / Viggle nodes / models を自動取得
- Huge Viggle weights はDockerに焼かない
- HF Xetを使用。RAM>=64GiBなら high-performance modeを自動ON
- BlockSparseAttention / ModelAttentionBackend / comfy-kitchen CUDA backendを検査
- 最後にRunPod標準 /start.sh へhandoff

GitHub Actions成功後、既存タグ:
ghcr.io/avalonkun420-commits/minerva-comfyui-base:v1
が薄型版に更新されます。

既存RunPod TemplateのContainer imageは変更不要。

RunPod Template:
- Container image: ghcr.io/avalonkun420-commits/minerva-comfyui-base:v1
- Container disk: 20〜30GB
- Volume disk: 100GB
- mount: /workspace
- HTTP: 8188
- ENABLE_JUPYTER=0

起動後の検査:
  /opt/minerva/status.sh
