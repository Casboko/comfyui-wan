# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
   PIP_PREFER_BINARY=1 \
   PYTHONUNBUFFERED=1 \
   CMAKE_BUILD_PARALLEL_LEVEL=8

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        python3-pip \
        curl ffmpeg ninja-build git aria2 git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    \
    # make Python3.12 the default python & pip
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    \
    python3.12 -m venv /opt/venv && \
    \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128

# Core Python tooling
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install packaging setuptools wheel

# Runtime libraries
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install pyyaml gdown triton comfy-cli jupyterlab jupyterlab-lsp \
        jupyter-server jupyter-server-terminals \
        ipykernel jupyterlab_code_formatter

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install sqlalchemy "huggingface_hub[hf_transfer]"

# ------------------------------------------------------------
# ComfyUI install
# ------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    /usr/bin/yes | comfy --workspace /ComfyUI install

FROM base AS final
# Make sure to use the virtual environment here too
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install opencv-python

RUN for repo in \
    https://github.com/Artificial-Sweetener/comfyui-WhiteRabbit.git \
    https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI.git \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    https://github.com/PGCRT/CRT-Nodes.git \
    https://github.com/Smirnov75/ComfyUI-mxToolkit.git \
    https://github.com/chibiace/ComfyUI-Chibi-Nodes.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/city96/ComfyUI-GGUF.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes.git \
    https://github.com/fblissjr/ComfyUI-WanSeamlessFlow.git \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/spacepxl/ComfyUI-Image-Filters.git \
    https://github.com/wallen0322/ComfyUI-Wan22FMLF.git \
    https://github.com/yolain/ComfyUI-Easy-Use.git \
    ; \
    do \
        cd /ComfyUI/custom_nodes; \
        repo_dir=$(basename "$repo" .git); \
        git clone "$repo"; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" ]; then \
            pip install -r "/ComfyUI/custom_nodes/$repo_dir/requirements.txt"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/install.py" ]; then \
            python "/ComfyUI/custom_nodes/$repo_dir/install.py"; \
        fi; \
    done

COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh

CMD ["/start_script.sh"]
