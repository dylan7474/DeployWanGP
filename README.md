# DeployWanGP

# Wan2GP Docker Deployment (Garuda Linux / RTX 4060 Ti)

A robust, automated deployment script for running **Wan2GP** locally using Docker. This environment is specifically optimized for NVIDIA RTX 4000 series GPUs (Ada Lovelace architecture) and engineered to be highly resilient over cellular/4G network connections.

## ✨ Key Features

* **Hardware Optimized:** Automatically patches compilation scripts to target CUDA compute capability `8.9` (RTX 4060 Ti), significantly reducing build times and improving VRAM efficiency.
* **Cellular/4G Resilient:** Bypasses standard Ubuntu mirrors in favor of Azure mirrors, forces strict packet retries, and disables HTTP pipelining to prevent `400 Bad Request` drops over mobile hotspots.
* **Root Privilege Bypass:** Ignores upstream restrictive entrypoint scripts to prevent `CUDA unknown error` crashes caused by locked `/dev/nvidia-caps` host files on Arch/Garuda Linux.
* **Shared Memory (IPC):** Uses `--ipc=host` to prevent CUDA memory conflicts when running alongside other AI containers (like SDNext or Open-WebUI).

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have the following installed on your host system:
* Docker Engine
* NVIDIA Container Toolkit (`nvidia-docker2` / `nvidia-container-toolkit`)
* Git

### 2. Deployment
Make the script executable and run it. The script is idempotent—you can run it multiple times safely to update the repository or rebuild the container.

```bash
chmod +x deploy.sh
./deploy.sh
3. Accessing the UI
Once the script completes and the container boots up, access the Gradio web interface at:

http://localhost:7862

📂 Directory Structure
The deployment script automatically separates your application code from your heavy user data to keep upgrades seamless.

Application Code: ~/Wan2GP (Live mounted into the container at /workspace)

User Data: ~/wan2gp-data

/ckpts - Downloaded video models and checkpoint weights.

/loras - Custom LoRA files.

/outputs - Generated MP4 videos and images.

🛠️ Troubleshooting
Issue: RuntimeError: CUDA unknown error
Symptom: The container starts, but the logs (docker logs wan2gp-video) show that PyTorch cannot initialize CUDA, often reporting zero available devices despite nvidia-smi seeing the GPU.
Cause: The host's NVIDIA Unified Memory kernel module (nvidia_uvm) is locked by a suspended container or a memory leak.
Fix:

Option A: Reboot your PC (fastest and cleanest).

Option B: Reload the driver module manually:

Bash
# Stop all running GPU containers
docker stop $(docker ps -q)
# Reload the unified memory module
sudo modprobe -r nvidia_uvm && sudo modprobe nvidia_uvm
# Restart Docker
sudo systemctl restart docker
Issue: Cannot connect to localhost:7862
Symptom: curl: (56) Recv failure: Connection reset by peer or the web page refuses to load.
Fix: Check the live container logs to see if Python is still downloading prerequisite models or if it crashed during initialization:

Bash
docker logs -f wan2gp-video
Issue: Remote Access Blocked
Symptom: You can access the UI on localhost, but not from another device on your network or via a reverse proxy domain.
Fix: The application runs on port 7860 inside the container but is mapped to 7862 on the host. Ensure your host firewall (UFW/Firewalld) allows traffic on port 7862, or set up a Caddy reverse proxy pointing to localhost:7862.

🔄 Updating Wan2GP
To pull the latest code from the upstream Wan2GP repository and rebuild the environment:

Run ./deploy.sh

The script will automatically reset local patches, git pull the latest main branch, re-apply the RTX/4G optimizations, and restart the container.
