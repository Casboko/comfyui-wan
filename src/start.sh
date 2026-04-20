#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

if ! which aria2 > /dev/null 2>&1; then
    echo "Installing aria2..."
    apt-get update && apt-get install -y aria2
else
    echo "aria2 is already installed"
fi

if ! which curl > /dev/null 2>&1; then
    echo "Installing curl..."
    apt-get update && apt-get install -y curl
else
    echo "curl is already installed"
fi

# Start SageAttention build in the background
echo "Starting SageAttention build..."
(
    export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
    cd /tmp
    git clone https://github.com/thu-ml/SageAttention.git
    cd SageAttention
    git reset --hard 68de379
    pip install -e .
    echo "SageAttention build completed" > /tmp/sage_build_done
) > /tmp/sage_build.log 2>&1 &
SAGE_PID=$!
echo "SageAttention build started in background (PID: $SAGE_PID)"

# Set the network volume path
NETWORK_VOLUME="/workspace"
URL="http://127.0.0.1:8188"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download_with_aria.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install onnxruntime-gpu &

KJNODES_COMMIT="204f6d5"
CUSTOM_NODE_REPOS=(
    "https://github.com/Artificial-Sweetener/comfyui-WhiteRabbit.git"
    "https://github.com/ashtar1984/comfyui-find-perfect-resolution.git"
    "https://github.com/ClownsharkBatwing/RES4LYF.git"
    "https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/LDNKS094/ComfyUI-Painter-I2V-AIO.git"
    "https://github.com/StableLlama/ComfyUI-basic_data_handling.git"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git"
    "https://github.com/WASasquatch/was-node-suite-comfyui.git"
    "https://github.com/filliptm/ComfyUI_Fill-Nodes.git"
    "https://github.com/jamesWalker55/comfyui-various.git"
    "https://github.com/kijai/ComfyUI-Florence2.git"
    "https://github.com/kijai/ComfyUI-GIMM-VFI.git"
    "https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git"
    "https://github.com/PGCRT/CRT-Nodes.git"
    "https://github.com/Smirnov75/ComfyUI-mxToolkit.git"
    "https://github.com/chibiace/ComfyUI-Chibi-Nodes.git"
    "https://github.com/chrisgoringe/cg-use-everywhere.git"
    "https://github.com/city96/ComfyUI-GGUF.git"
    "https://github.com/cubiq/ComfyUI_essentials.git"
    "https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes.git"
    "https://github.com/fblissjr/ComfyUI-WanSeamlessFlow.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/melMass/comfy_mtb.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/spacepxl/ComfyUI-Image-Filters.git"
    "https://github.com/wallen0322/ComfyUI-Wan22FMLF.git"
    "https://github.com/yuvraj108c/ComfyUI-Upscaler-Tensorrt.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
)

DEPRECATED_CUSTOM_NODE_DIRS=(
    "ComfyUI-PainterI2Vadvanced"
)

remove_deprecated_custom_node_dirs() {
    local node_dir

    for node_dir in "${DEPRECATED_CUSTOM_NODE_DIRS[@]}"; do
        if [ -d "$CUSTOM_NODES_DIR/$node_dir" ]; then
            echo "🧹 Removing deprecated custom node: $node_dir"
            rm -rf "$CUSTOM_NODES_DIR/$node_dir"
        fi
    done
}

sync_custom_node_repo() {
    local repo="$1"
    local repo_dir
    repo_dir=$(basename "$repo" .git)

    if [ ! -d "$CUSTOM_NODES_DIR/$repo_dir" ]; then
        cd "$CUSTOM_NODES_DIR" || exit 1
        git clone "$repo"
    else
        echo "Updating $repo_dir"
        cd "$CUSTOM_NODES_DIR/$repo_dir" || exit 1
        git pull
    fi

    if [ "$repo_dir" = "ComfyUI-KJNodes" ]; then
        cd "$CUSTOM_NODES_DIR/$repo_dir" || exit 1
        git reset --hard "$KJNODES_COMMIT"
    fi
}

install_custom_node_deps() {
    local repo="$1"
    local repo_dir
    repo_dir=$(basename "$repo" .git)
    local repo_path="$CUSTOM_NODES_DIR/$repo_dir"

    if [ -f "$repo_path/requirements.txt" ]; then
        echo "🔧 Installing $repo_dir requirements..."
        pip install --no-cache-dir -r "$repo_path/requirements.txt"
    fi

    if [ -f "$repo_path/install.py" ]; then
        echo "🔧 Running $repo_dir install.py..."
        python "$repo_path/install.py"
    fi
}

remove_deprecated_custom_node_dirs

for repo in "${CUSTOM_NODE_REPOS[@]}"; do
    sync_custom_node_repo "$repo"
done

for repo in "${CUSTOM_NODE_REPOS[@]}"; do
    install_custom_node_deps "$repo"
done


export change_preview_method="true"


# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"
MODEL_DOWNLOAD_MAX_PARALLEL="${MODEL_DOWNLOAD_MAX_PARALLEL:-2}"
CIVITAI_MAX_PARALLEL="${CIVITAI_MAX_PARALLEL:-4}"
MODEL_DOWNLOAD_PIDS=()
CIVITAI_DOWNLOAD_PIDS=()

prune_finished_pids() {
    local -n pid_array="$1"
    local active_pids=()
    local pid

    for pid in "${pid_array[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            active_pids+=("$pid")
        fi
    done

    pid_array=("${active_pids[@]}")
}

wait_for_slot() {
    local limit="$1"
    local array_name="$2"

    while true; do
        prune_finished_pids "$array_name"
        local -n pid_array="$array_name"
        if [ "${#pid_array[@]}" -lt "$limit" ]; then
            break
        fi
        sleep 1
    done
}

wait_for_downloads() {
    local array_name="$1"
    local label="$2"
    local status=0
    local pid
    local -n pid_array="$array_name"

    for pid in "${pid_array[@]}"; do
        if ! wait "$pid"; then
            echo "❌ ${label} download failed (PID: $pid)"
            status=1
        fi
    done

    pid_array=()
    return "$status"
}

ensure_model_alias() {
    local source_path="$1"
    local target_path="$2"

    if [ ! -f "$source_path" ]; then
        echo "⚠️  Alias source missing, skipping: $source_path"
        return 1
    fi

    mkdir -p "$(dirname "$target_path")"
    rm -f "$target_path"

    if ln -s "$source_path" "$target_path" 2>/dev/null; then
        echo "🔗 Linked model alias: $target_path -> $source_path"
    else
        cp -f "$source_path" "$target_path"
        echo "📄 Copied model alias: $target_path"
    fi
}

is_huggingface_resolve_url() {
    local url="$1"
    [[ "$url" =~ ^https://huggingface\.co/.+/resolve/.+$ ]]
}

download_model_huggingface() {
    local url="$1"
    local destination_dir="$2"
    local destination_file="$3"

    python - "$url" "$destination_dir" "$destination_file" <<'PY'
import os
import shutil
import sys
from pathlib import Path
from urllib.parse import urlparse

from huggingface_hub import hf_hub_download

url, destination_dir, destination_file = sys.argv[1:4]
parsed = urlparse(url)
parts = parsed.path.lstrip("/").split("/")
if len(parts) < 5 or parts[2] != "resolve":
    raise SystemExit(f"Unsupported Hugging Face resolve URL: {url}")

repo_id = f"{parts[0]}/{parts[1]}"
filename = "/".join(parts[4:])
token = (os.environ.get("HF_TOKEN") or "").strip() or None
destination_dir_path = Path(destination_dir)
destination_path = destination_dir_path / destination_file
destination_dir_path.mkdir(parents=True, exist_ok=True)

local_path = Path(
    hf_hub_download(
        repo_id=repo_id,
        filename=filename,
        local_dir=str(destination_dir_path),
        token=token,
    )
)

if local_path.resolve() != destination_path.resolve():
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(local_path), str(destination_path))
PY
}

download_model_civitai_model_version() {
    local model_version_id="$1"
    local full_path="$2"

    local destination_dir
    destination_dir=$(dirname "$full_path")
    local destination_file
    destination_file=$(basename "$full_path")

    mkdir -p "$destination_dir"

    if [ -f "$full_path" ]; then
        local size_bytes
        size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        local size_mb=$((size_bytes / 1024 / 1024))

        if [ "$size_bytes" -lt 10485760 ]; then
            echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
            rm -f "$full_path"
        else
            echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
            return 0
        fi
    fi

    if [ -f "${full_path}.aria2" ]; then
        echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
        rm -f "${full_path}.aria2"
        rm -f "$full_path"
    fi

    echo "📥 Downloading CivitAI model version $model_version_id to $destination_dir/$destination_file..."

    wait_for_slot "$MODEL_DOWNLOAD_MAX_PARALLEL" MODEL_DOWNLOAD_PIDS

    python3 - "$model_version_id" "$destination_dir" "$destination_file" <<'PY' &
import os
import subprocess
import sys
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

import requests

model_version_id, destination_dir, destination_file = sys.argv[1:4]
token = (os.environ.get("civitai_token") or "").strip()
headers = {"Authorization": f"Bearer {token}"} if token else {}


def append_token(url: str, token_value: str) -> str:
    if not token_value:
        return url
    parsed = urlparse(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query["token"] = token_value
    return urlunparse(parsed._replace(query=urlencode(query)))


meta_url = f"https://civitai.com/api/v1/model-versions/{model_version_id}"
meta_response = requests.get(meta_url, headers=headers, timeout=30)
meta_response.raise_for_status()
meta = meta_response.json()
files = meta.get("files") or []
if not files:
    raise SystemExit(f"No files found for CivitAI model version {model_version_id}")

download_url = files[0].get("downloadUrl") or f"https://civitai.com/api/download/models/{model_version_id}"
download_url = append_token(download_url, token)

redirect_response = requests.get(
    download_url,
    headers=headers,
    allow_redirects=False,
    timeout=30,
)
if redirect_response.status_code not in (301, 302, 303, 307, 308):
    raise SystemExit(
        f"Failed to resolve download URL for CivitAI model version {model_version_id}: "
        f"HTTP {redirect_response.status_code}"
    )

resolved_url = redirect_response.headers.get("Location")
if not resolved_url:
    raise SystemExit(f"Missing redirect location for CivitAI model version {model_version_id}")

os.makedirs(destination_dir, exist_ok=True)
subprocess.run(
    [
        "aria2c",
        "-x",
        "16",
        "-s",
        "16",
        "-k",
        "1M",
        "--continue=true",
        "--auto-file-renaming=false",
        "--allow-overwrite=true",
        "-d",
        destination_dir,
        "-o",
        destination_file,
        resolved_url,
    ],
    check=True,
)
PY

    MODEL_DOWNLOAD_PIDS+=("$!")

    echo "Download started in background for $destination_file"
}

download_and_extract_civitai_archive_model_version() {
    local model_version_id="$1"
    local destination_dir="$2"
    local extract_subdir="$3"
    local extract_path="$destination_dir/$extract_subdir"
    local completion_marker="$extract_path/.civitai-model-version-${model_version_id}.complete"

    mkdir -p "$destination_dir"

    if [ -f "$completion_marker" ]; then
        echo "✅ CivitAI archive $model_version_id already extracted, skipping: $extract_path"
        return 0
    fi

    if [ -d "$extract_path" ]; then
        echo "🧹 Removing incomplete CivitAI archive extraction: $extract_path"
        rm -rf "$extract_path"
    fi

    echo "📦 Downloading and extracting CivitAI archive model version $model_version_id to $extract_path..."

    wait_for_slot "$MODEL_DOWNLOAD_MAX_PARALLEL" MODEL_DOWNLOAD_PIDS

    python3 - "$model_version_id" "$destination_dir" "$extract_subdir" <<'PY' &
import json
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

import requests

model_version_id, destination_dir, extract_subdir = sys.argv[1:4]
token = (os.environ.get("civitai_token") or "").strip()
headers = {"Authorization": f"Bearer {token}"} if token else {}


def append_token(url: str, token_value: str) -> str:
    if not token_value:
        return url
    parsed = urlparse(url)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query["token"] = token_value
    return urlunparse(parsed._replace(query=urlencode(query)))


def safe_extract(zf: zipfile.ZipFile, target_dir: Path) -> None:
    target_root = target_dir.resolve()
    for member in zf.infolist():
        member_target = (target_dir / member.filename).resolve()
        if member_target != target_root and target_root not in member_target.parents:
            raise SystemExit(f"Refusing to extract archive entry outside target dir: {member.filename}")
    zf.extractall(target_dir)


meta_url = f"https://civitai.com/api/v1/model-versions/{model_version_id}"
meta_response = requests.get(meta_url, headers=headers, timeout=30)
meta_response.raise_for_status()
meta = meta_response.json()
files = meta.get("files") or []
if not files:
    raise SystemExit(f"No files found for CivitAI model version {model_version_id}")

archive_file = next((f for f in files if (f.get("type") or "").lower() == "model"), files[0])
archive_name = archive_file.get("name") or f"{model_version_id}.zip"
if not archive_name.lower().endswith(".zip"):
    raise SystemExit(
        f"CivitAI model version {model_version_id} is not a zip archive: {archive_name}"
    )

download_url = archive_file.get("downloadUrl") or f"https://civitai.com/api/download/models/{model_version_id}"
download_url = append_token(download_url, token)

destination_root = (Path(destination_dir) / extract_subdir).resolve()
marker_path = destination_root / f".civitai-model-version-{model_version_id}.complete"

with tempfile.TemporaryDirectory(prefix=f"civitai-{model_version_id}-", dir=destination_dir) as temp_dir:
    temp_path = Path(temp_dir)
    archive_path = temp_path / archive_name

    with requests.get(
        download_url,
        headers=headers,
        stream=True,
        allow_redirects=True,
        timeout=(30, 300),
    ) as response:
        response.raise_for_status()
        with archive_path.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=4 * 1024 * 1024):
                if chunk:
                    handle.write(chunk)

    if archive_path.stat().st_size < 10 * 1024 * 1024:
        raise SystemExit(
            f"Downloaded archive for CivitAI model version {model_version_id} looks too small: "
            f"{archive_path.stat().st_size} bytes"
        )

    if destination_root.exists():
        shutil.rmtree(destination_root)
    destination_root.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(archive_path) as archive:
        safe_extract(archive, destination_root)

    extracted_model_files = sorted(
        str(path.relative_to(destination_root))
        for path in destination_root.rglob("*")
        if path.is_file() and path.suffix.lower() in {".safetensors", ".gguf", ".pth", ".pt", ".bin"}
    )
    if not extracted_model_files:
        raise SystemExit(
            f"No model files were found after extracting CivitAI model version {model_version_id}"
        )

    marker_path.write_text(
        json.dumps(
            {
                "model_version_id": model_version_id,
                "archive_name": archive_name,
                "files": extracted_model_files,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
PY

    MODEL_DOWNLOAD_PIDS+=("$!")

    echo "Archive download started in background for CivitAI model version $model_version_id"
}

# Function to download a model using hf_transfer or aria2c
download_model() {
    local url="$1"
    local full_path="$2"

    local destination_dir=$(dirname "$full_path")
    local destination_file=$(basename "$full_path")

    mkdir -p "$destination_dir"

    # Simple corruption check: file < 10MB or .aria2 files
    if [ -f "$full_path" ]; then
        local size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        local size_mb=$((size_bytes / 1024 / 1024))

        if [ "$size_bytes" -lt 10485760 ]; then  # Less than 10MB
            echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
            rm -f "$full_path"
        else
            echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
            return 0
        fi
    fi

    # Check for and remove .aria2 control files
    if [ -f "${full_path}.aria2" ]; then
        echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
        rm -f "${full_path}.aria2"
        rm -f "$full_path"  # Also remove any partial file
    fi

    echo "📥 Downloading $destination_file to $destination_dir..."

    wait_for_slot "$MODEL_DOWNLOAD_MAX_PARALLEL" MODEL_DOWNLOAD_PIDS

    if is_huggingface_resolve_url "$url"; then
        download_model_huggingface "$url" "$destination_dir" "$destination_file" &
    else
        # Download without falloc (since it's not supported in your environment)
        aria2c -x 16 -s 16 -k 1M --continue=true -d "$destination_dir" -o "$destination_file" "$url" &
    fi

    MODEL_DOWNLOAD_PIDS+=("$!")

    echo "Download started in background for $destination_file"
}

run_optional_downloads() {
    ensure_model_alias \
        "/comfyui-wan/4xLSDIR.pth" \
        "$UPSCALE_MODELS_DIR/4xLSDIR.pth" || true

    echo "Downloading managed Hugging Face / direct URL models..."
    download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_high_noise_14B_fp16.safetensors"
    download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_low_noise_14B_fp16.safetensors"
    download_model "https://huggingface.co/obsxrver/wan2.2-i2v-lightx2v-260412/resolve/main/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_720p_260412.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_720p_260412.safetensors"
    download_model "https://huggingface.co/obsxrver/wan2.2-i2v-lightx2v-260412/resolve/main/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_720p_260412.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_720p_260412.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.1-Distill-Models/resolve/main/wan2.1_i2v_480p_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_480p_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.1-Distill-Models/resolve/main/wan2.1_i2v_720p_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_720p_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors"
    download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$TEXT_ENCODERS_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" "$TEXT_ENCODERS_DIR/umt5-xxl-enc-bf16.safetensors"
    download_model "https://huggingface.co/NSFW-API/NSFW-Wan-UMT5-XXL/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors" "$TEXT_ENCODERS_DIR/nsfw_wan_umt5-xxl_fp8_scaled.safetensors"
    download_model "https://huggingface.co/zootkitty/nsfw_wan_umt5-xxl_bf16_fixed/resolve/main/nsfw_wan_umt5-xxl_bf16_fixed.safetensors" "$TEXT_ENCODERS_DIR/nsfw_wan_umt5-xxl_bf16_fixed.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" "$TEXT_ENCODERS_DIR/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors"
    download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "$CLIP_VISION_DIR/clip_vision_h.safetensors"
    download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$VAE_DIR/wan_2.1_vae.safetensors"
    download_model "https://huggingface.co/obsxrver/wan2.2-i2v-lightx2v-260412/resolve/main/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_720p_260412.safetensors" "$LORAS_DIR/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_720p_260412.safetensors"
    download_model "https://huggingface.co/obsxrver/wan2.2-i2v-lightx2v-260412/resolve/main/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_720p_260412.safetensors" "$LORAS_DIR/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_720p_260412.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors" "$LORAS_DIR/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors" "$LORAS_DIR/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/high_noise_model.safetensors" "$LORAS_DIR/Wan2.2-Lightning/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/high_noise_model.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/low_noise_model.safetensors" "$LORAS_DIR/Wan2.2-Lightning/Wan2.2-I2V-A14B-4steps-lora-rank64-Seko-V1/low_noise_model.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.1-Distill-Loras/resolve/main/wan2.1_i2v_lora_rank64_lightx2v_4step.safetensors" "$LORAS_DIR/wan2.1_i2v_lora_rank64_lightx2v_4step.safetensors"
    download_and_extract_civitai_archive_model_version "2174159" "$LORAS_DIR" "CivitAI/wan22-2d-animation-effects-2d"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors" "$LORAS_DIR/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_Lightx2v/Wan_2_2_I2V_A14B_HIGH_lightx2v_4step_lora_260412_rank_64_fp16.safetensors" "$LORAS_DIR/Wan_2_2_I2V_A14B_HIGH_lightx2v_4step_lora_260412_rank_64_fp16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_Lightx2v/Wan_2_2_I2V_A14B_LOW_lightx2v_4step_lora_260412_rank_64_fp16.safetensors" "$LORAS_DIR/Wan_2_2_I2V_A14B_LOW_lightx2v_4step_lora_260412_rank_64_fp16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_Lightx2v/Wan_2_2_I2V_A14B_HIGH_lightx2v_4step_lora_260412_rank_256_fp16.safetensors" "$LORAS_DIR/Wan_2_2_I2V_A14B_HIGH_lightx2v_4step_lora_260412_rank_256_fp16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_Lightx2v/Wan_2_2_I2V_A14B_LOW_lightx2v_4step_lora_260412_rank_256_fp16.safetensors" "$LORAS_DIR/Wan_2_2_I2V_A14B_LOW_lightx2v_4step_lora_260412_rank_256_fp16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_Lightx2v/Wan_2_2_I2V_A14B_HIGH_lightx2v_MoE_distill_lora_rank_64_bf16.safetensors" "$LORAS_DIR/Wan_2_2_I2V_A14B_HIGH_lightx2v_MoE_distill_lora_rank_64_bf16.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.2-I2V-A14B-Moe-Distill-Lightx2v/resolve/main/loras/low_noise_model_rank64.safetensors" "$LORAS_DIR/Wan2.2-I2V-A14B-Moe-Distill-Lightx2v_low_noise_model_rank64.safetensors"
    download_model "https://huggingface.co/lightx2v/Wan2.1-I2V-14B-480P-StepDistill-CfgDistill-Lightx2v/resolve/main/loras/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors" "$LORAS_DIR/Wan21_I2V_14B_lightx2v_cfg_step_distill_lora_rank64.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors" "$LORAS_DIR/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors"
    download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors" "$LORAS_DIR/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors"
    download_model_civitai_model_version "2540892" "$UNET_MODELS_DIR/wan22EnhancedNSFWSVICamera_nsfwFASTMOVEV2Q8H.gguf"
    download_model_civitai_model_version "2540896" "$UNET_MODELS_DIR/wan22EnhancedNSFWSVICamera_nsfwFASTMOVEV2Q8L.gguf"

    # Existing workflows already reference rife49.pth, so prefetch it at pod startup.
    download_model "https://huggingface.co/marduk191/rife/resolve/main/rife49.pth" "$CUSTOM_NODES_DIR/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth"

    # SeedVR2 is the current high-quality video upscaling option with both
    # a quality-first FP16 preset and a lower-VRAM Q8 GGUF preset.
    download_model "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp16.safetensors" "$SEEDVR2_MODELS_DIR/seedvr2_ema_3b_fp16.safetensors"
    download_model "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b-Q8_0.gguf" "$SEEDVR2_MODELS_DIR/seedvr2_ema_3b-Q8_0.gguf"
    download_model "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors" "$SEEDVR2_MODELS_DIR/ema_vae_fp16.safetensors"

    echo "⏳ Waiting for managed model downloads to complete..."
    if ! wait_for_downloads MODEL_DOWNLOAD_PIDS "managed model"; then
        return 1
    fi

    ensure_model_alias \
        "$TEXT_ENCODERS_DIR/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" \
        "$CLIP_VISION_DIR/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors"

    CHECKPOINT_IDS_TO_DOWNLOAD="${CHECKPOINT_IDS_TO_DOWNLOAD:-replace_with_ids}"

    DEFAULT_LORAS_IDS_TO_DOWNLOAD="2263030,2263094,2293529,2293622,2250571,2250590,2377549,2377566,2098405,2098396,2245356,2245426,2545249,2545246,2156392,2156435,2169837,2169847,2648813,2648814,2663475,2663487,2377035,2377244,2235299,2235288,2325788,2191446,2441730,2445044,2212384,2212394,2352366,2352388,2445168,2445176,2187729,2187757,2448064,2448070,2272024,2272102,2620366,2622170,2785769,2786571,2510280,2510218,2595899,2595905,2303927,2303966,2308249,2308253,2308339,2308328,2176450,2178869,2460386,2460428,2197409,2215731,2430424,2430183,2303232,2303184,2438671,2433303,2373814,2373843,2779234,2779292,2516837,2516839"
    DEFAULT_LORAS_IDS_TO_DOWNLOAD+=",2073605,2083303,2343934,2344329,2251804,2251839,2239947,2239942,2191786,2191798"
    DEFAULT_LORAS_IDS_TO_DOWNLOAD+=",2718460,2722289,2426143,2426138,2116008,2116027,2579567,2579518,2631919,2631948"
    DEFAULT_LORAS_IDS_TO_DOWNLOAD+=",2484657,2538990,2632191,2632200,2212521,2212510,2207480,2207776,2254373,2254403"
    DEFAULT_LORAS_IDS_TO_DOWNLOAD+=",2477983,2477975,2161023,2161067,2342652,2342660,2332735,2332853,2246694,2246669"
    if [ -z "${LORAS_IDS_TO_DOWNLOAD:-}" ] || [ "$LORAS_IDS_TO_DOWNLOAD" = "replace_with_ids" ]; then
        LORAS_IDS_TO_DOWNLOAD="$DEFAULT_LORAS_IDS_TO_DOWNLOAD"
    fi

    declare -A MODEL_CATEGORIES=(
        ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="$CHECKPOINT_IDS_TO_DOWNLOAD"
        ["$NETWORK_VOLUME/ComfyUI/models/loras"]="$LORAS_IDS_TO_DOWNLOAD"
    )

    download_count=0

    for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
        mkdir -p "$TARGET_DIR"
        MODEL_IDS_STRING="${MODEL_CATEGORIES[$TARGET_DIR]}"

        if [[ "$MODEL_IDS_STRING" == "replace_with_ids" ]]; then
            echo "⏭️  Skipping downloads for $TARGET_DIR (default value detected)"
            continue
        fi

        IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

        for MODEL_ID in "${MODEL_IDS[@]}"; do
            sleep 1
            wait_for_slot "$CIVITAI_MAX_PARALLEL" CIVITAI_DOWNLOAD_PIDS
            echo "🚀 Scheduling download: $MODEL_ID to $TARGET_DIR"
            (cd "$TARGET_DIR" && download_with_aria.py -m "$MODEL_ID") &
            CIVITAI_DOWNLOAD_PIDS+=("$!")
            ((download_count++))
        done
    done

    echo "📋 Scheduled $download_count downloads in background"
    echo "⏳ Waiting for downloads to complete..."
    if ! wait_for_downloads CIVITAI_DOWNLOAD_PIDS "CivitAI"; then
        return 1
    fi

    echo "✅ All models downloaded successfully!"
    echo "All downloads completed!"
    echo "Finished downloading models!"

    echo "Renaming loras downloaded as zip files to safetensors files"
    cd "$LORAS_DIR" || return 1
    for file in *.zip; do
        [ -e "$file" ] || break
        mv "$file" "${file%.zip}.safetensors"
    done
}

# Define base paths
DIFFUSION_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/diffusion_models"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
CLIP_VISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"
VAE_DIR="$NETWORK_VOLUME/ComfyUI/models/vae"
LORAS_DIR="$NETWORK_VOLUME/ComfyUI/models/loras"
DETECTION_DIR="$NETWORK_VOLUME/ComfyUI/models/detection"
UNET_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/unet"
UPSCALE_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/upscale_models"
SEEDVR2_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/SEEDVR2"


echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

# Ensure the file exists in the current directory before moving it
cd /

SOURCE_DIR="/comfyui-wan/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

SOURCE_DIR="/comfyui-wan/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

# Loop over each subdirectory in the source directory
for dir in "$SOURCE_DIR"/*/; do
    # Skip if no directories match (empty glob)
    [[ -d "$dir" ]] || continue

    dir_name="$(basename "$dir")"
    dest_dir="$WORKFLOW_DIR/$dir_name"

    if [[ -e "$dest_dir" ]]; then
        echo "Directory already exists in destination. Deleting source: $dir"
        rm -rf "$dir"
    else
        echo "Moving: $dir to $WORKFLOW_DIR"
        mv "$dir" "$WORKFLOW_DIR/"
    fi
done

if [ "$change_preview_method" == "true" ]; then
    echo "Updating default preview method..."
    sed -i '/id: *'"'"'VHS.LatentPreview'"'"'/,/defaultValue:/s/defaultValue: false/defaultValue: true/' $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite/web/js/VHS.core.js
    CONFIG_PATH="/ComfyUI/user/default/ComfyUI-Manager"
    CONFIG_FILE="$CONFIG_PATH/config.ini"

# Ensure the directory exists
mkdir -p "$CONFIG_PATH"

# Create the config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.ini..."
    cat <<EOL > "$CONFIG_FILE"
[default]
preview_method = auto
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
skip_migration_check = False
always_lazy_install = False
network_mode = public
db_mode = cache
EOL
else
    echo "config.ini already exists. Updating preview_method..."
    sed -i 's/^preview_method = .*/preview_method = auto/' "$CONFIG_FILE"
fi
echo "Config file setup complete!"
    echo "Default preview method updated to 'auto'"
else
    echo "Skipping preview method update (change_preview_method is not 'true')."
fi

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc


echo "✅ Custom node dependency installs complete"

# Wait for SageAttention build to complete
echo "Waiting for SageAttention build to complete..."
while ! [ -f /tmp/sage_build_done ]; do
    if ps -p $SAGE_PID > /dev/null 2>&1; then
        echo "⚙️  SageAttention build in progress, this may take up to 5 minutes."
        sleep 5
    else
        # Process finished but no completion marker - check if it failed
        if ! [ -f /tmp/sage_build_done ]; then
            echo "⚠️  SageAttention build process ended unexpectedly. Check logs at /tmp/sage_build.log"
            echo "Continuing with ComfyUI startup..."
            break
        fi
    fi
done

if [ -f /tmp/sage_build_done ]; then
    echo "✅ SageAttention build completed successfully!"
fi

pip install comfy-aimdo
pip install comfy-kitchen

# Start ComfyUI

echo "▶️  Starting ComfyUI"

nohup python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen --enable-cors-header '*' --use-sage-attention > "$NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log" 2>&1 &

    # Counter for timeout
    counter=0
    max_wait=70

    until curl --silent --fail "$URL" --output /dev/null; do
        if [ $counter -ge $max_wait ]; then
            echo "⚠️  ComfyUI should be up by now. If it's not running, there's probably an error."
            echo ""
            echo "🛠️  Troubleshooting Tips:"
            echo "1. Make sure that your CUDA Version is set to 12.8/12.9 by selecting that in the additional filters tab before deploying the template"
            echo "2. If you are deploying using network storage, try deploying without it"
            echo "3. If you are using a B200 GPU, it is currently not supported"
            echo "4. If all else fails, open the web terminal by clicking \"connect\", \"enable web terminal\" and running:"
            echo "   cat comfyui_${RUNPOD_POD_ID}_nohup.log"
            echo "   This should show a ComfyUI error. Please paste the error in HearmemanAI Discord Server for assistance."
            echo ""
            echo "📋 Startup logs location: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
            break
        fi

        echo "🔄  ComfyUI Starting Up... You can view the startup logs here: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
        sleep 2
        counter=$((counter + 2))
    done

    # Only show success message if curl succeeded
    if curl --silent --fail "$URL" --output /dev/null; then
        echo "🚀 ComfyUI is UP"
        (
            if ! run_optional_downloads; then
                echo "⚠️  Optional model and LoRA downloads failed. ComfyUI will continue running."
            fi
        ) &
        echo "📥 Optional model and LoRA downloads started in background (PID: $!)"
    fi

    sleep infinity
