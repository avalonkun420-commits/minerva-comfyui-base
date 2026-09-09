MINERVA COMFYUI BASE v1

1) GitHubで public repository を作る
   名前: minerva-comfyui-base

2) このZIPの中身をリポジトリ直下へアップロード
   .github/workflows/build.yml の階層はそのまま。

3) GitHub > Actions > Build MINERVA ComfyUI Base > Run workflow
   完了後、Packages の minerva-comfyui-base を Public にする。

4) RunPod Template
   Name: MINERVA COMFYUI BASE v1
   Type: Pods
   Compute: NVIDIA / GPU
   Public template: OFF
   Container image:
     ghcr.io/<githubユーザー名小文字>/minerva-comfyui-base:v1
   Start command: 空欄
   Container disk: 20 GB
   Persistent storage / Volume disk: 100 GB
   Volume mount: /workspace
   Ports:
     8188/http
     8888/http
   Env:
     ENABLE_JUPYTER=1
     JUPYTER_TOKEN=<任意の長い文字列>

5) Deploy後の確認
   Web Terminal:
     /opt/minerva/status.sh

   合格:
     BlockSparseAttention: FOUND
     ModelAttentionBackend: FOUND
     8188: OPEN
     8888: OPEN

このBASEにはViggleモデルやViggle custom nodeはまだ入れない。
BASEが成功した後、MINERVA VIGGLE LABを上に載せる。
