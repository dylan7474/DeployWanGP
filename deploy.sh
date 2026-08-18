#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Wan2GP Master Deployment Script for Garuda Linux / RTX 4060 Ti
# ==============================================================================

# Configuration
CONTAINER_NAME="wan2gp-video"
IMAGE_NAME="wan2gp:latest"
HOST_PORT="7862"
REPO_URL="https://github.com/deepbeepmeep/Wan2GP.git"
APP_DIR="$HOME/Wan2GP"
DATA_DIR="$HOME/wan2gp-data"
CUDA_ARCH="8.9"  # Target architecture for NVIDIA RTX 4060 Ti

echo "[1/6] Syncing Wan2GP repository..."
if [ ! -d "$APP_DIR" ]; then
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
else
    cd "$APP_DIR"
    # Reset any previous patches to avoid compounding changes on updates
    git checkout Dockerfile setup.py entrypoint.sh 2>/dev/null || true
    git pull origin main || git pull
fi

echo "[2/6] Preparing host storage directories..."
mkdir -p "${DATA_DIR}/ckpts" "${DATA_DIR}/outputs" "${DATA_DIR}/loras"
chmod -R 777 "${DATA_DIR}"

echo "[3/6] Applying Setup & Build Patches..."

# Patch 1: setup.py (Fixes compute capability for Ada Lovelace / RTX 4060 Ti)
cat << 'PYEOF' > patch_setup.py
import os
with open('setup.py', 'r') as f:
    content = f.read()

arch_list = os.environ.get('TORCH_CUDA_ARCH_LIST', '8.9')
arch_set = '{' + ', '.join([f'"{arch}"' for arch in arch_list.split(';')]) + '}'

old_section = '''compute_capabilities = set()
device_count = torch.cuda.device_count()
for i in range(device_count):
    major, minor = torch.cuda.get_device_capability(i)
    if major < 8:
        warnings.warn(f"skipping GPU {i} with compute capability {major}.{minor}")
        continue
    compute_capabilities.add(f"{major}.{minor}")'''

new_section = 'compute_capabilities = ' + arch_set + '''
print(f"Manually set compute capabilities: {compute_capabilities}")'''

content = content.replace(old_section, new_section)
with open('setup.py', 'w') as f:
    f.write(content)
PYEOF

# Patch 2: Dockerfile (Fixes 4G cellular drops, Azure mirror, & heredoc syntax)
cat << 'PYEOF' > patch_dockerfile.py
import re

with open('Dockerfile', 'r') as f:
    content = f.read()

# Fix heredoc COPY syntax for legacy Docker builders
content = re.sub(r'COPY <<EOF /tmp/patch_setup\.py\n.*?EOF', 'COPY patch_setup.py /tmp/patch_setup.py', content, flags=re.DOTALL)

# Inject Azure mirrors and strict retries immediately after the FROM instruction
apt_fix = """
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://azure.archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list && \\
    sed -i 's|http://security.ubuntu.com/ubuntu/|http://azure.archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list && \\
    echo 'Acquire::Retries "10";' > /etc/apt/apt.conf.d/80retries && \\
    echo 'Acquire::http::No-Cache "true";' >> /etc/apt/apt.conf.d/80retries && \\
    echo 'Acquire::http::Pipeline-Depth "0";' >> /etc/apt/apt.conf.d/80retries
"""
content = re.sub(r'(FROM [^\n]+\n)', r'\1' + apt_fix, content, count=1)

with open('Dockerfile', 'w') as f:
    f.write(content)
PYEOF

# Execute patchers
python3 patch_dockerfile.py

echo "[4/6] Building Wan2GP Docker image..."
# (If the image is already built and cached, Docker will breeze through this in seconds)
docker build \
    --build-arg CUDA_ARCHITECTURES="${CUDA_ARCH}" \
    -t "$IMAGE_NAME" .

echo "[5/6] Cleaning up old instances..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

echo "[6/6] Launching GPU container..."
# - Bypasses buggy entrypoint script with direct python3 execution
# - Maintains root privileges to avoid /dev/nvidia-caps access denial
# - Binds Gradio server to 0.0.0.0 for external network access
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --gpus all \
    --ipc=host \
    --privileged \
    -u root \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,video \
    -e SERVER_NAME="0.0.0.0" \
    -e GRADIO_SERVER_NAME="0.0.0.0" \
    -e PYTHONUNBUFFERED=1 \
    -p "${HOST_PORT}:7860" \
    -v "${APP_DIR}:/workspace" \
    -v "${DATA_DIR}/ckpts:/workspace/ckpts" \
    -v "${DATA_DIR}/outputs:/workspace/outputs" \
    -v "${DATA_DIR}/loras:/workspace/loras" \
    --entrypoint python3 \
    "$IMAGE_NAME" \
    wgp.py

echo "=================================================================="
echo "✅ Master Deployment Complete!"
echo "🎥 UI Access:   http://localhost:${HOST_PORT}"
echo "📂 App Code:    ${APP_DIR}"
echo "🗄️  User Data:   ${DATA_DIR}"
echo "📜 Live Logs:   docker logs -f ${CONTAINER_NAME}"
echo "=================================================================="
