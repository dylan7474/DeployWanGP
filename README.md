# DeployWanGP

DeployWanGP provides a single Bash script for building and running
[Wan2GP](https://github.com/deepbeepmeep/Wan2GP) in Docker. The defaults target
Garuda/Arch Linux with an NVIDIA RTX 4060 Ti (CUDA compute capability 8.9), but
the configuration variables at the top of `deploy.sh` can be adjusted for
another host or GPU.

## What the script does

Each run of `deploy.sh`:

1. Clones Wan2GP into `~/Wan2GP`, or resets the upstream build files and pulls
   the latest upstream changes when that directory already exists.
2. Creates persistent checkpoint, output, and LoRA directories under
   `~/wan2gp-data`.
3. Generates build-time patches that set the CUDA architecture explicitly and
   configure Ubuntu's Azure package mirror with additional APT retry settings.
4. Builds the local `wan2gp:latest` image.
5. Replaces any existing `wan2gp-video` container and starts the new container.

The application is published at <http://localhost:7862> by default.

> [!IMPORTANT]
> An update discards local changes to `Dockerfile`, `setup.py`, and
> `entrypoint.sh` inside `~/Wan2GP`. Commit or back up changes to those files
> before running the script again.

## Prerequisites

- A Linux host with a supported NVIDIA GPU and a working NVIDIA driver
- [Docker Engine](https://docs.docker.com/engine/install/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- Git and Python 3
- Enough free disk space for the Docker image, model checkpoints, and outputs

Confirm that Docker can access the GPU before deploying:

```bash
docker run --rm --gpus all ubuntu nvidia-smi
```

## Deploy

Clone this repository, then run:

```bash
chmod +x deploy.sh
./deploy.sh
```

Follow the startup logs until the service is ready:

```bash
docker logs -f wan2gp-video
```

Open <http://localhost:7862> in a browser. Startup can take longer on the first
run while dependencies or models are downloaded.

## Configuration

The deployment settings are constants near the top of `deploy.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_NAME` | `wan2gp-video` | Name of the running Docker container |
| `IMAGE_NAME` | `wan2gp:latest` | Locally built image name and tag |
| `HOST_PORT` | `7862` | Host port mapped to container port 7860 |
| `APP_DIR` | `~/Wan2GP` | Upstream source checkout |
| `DATA_DIR` | `~/wan2gp-data` | Persistent application data |
| `CUDA_ARCH` | `8.9` | CUDA compute capability used for the build |

Edit these values before running the script when the defaults do not match the
host. In particular, set `CUDA_ARCH` to the compute capability of the target
GPU; the default is intended for an RTX 4060 Ti.

## Persistent data

The source checkout and user data are mounted into the container:

```text
~/Wan2GP/                 -> /workspace
~/wan2gp-data/ckpts/      -> /workspace/ckpts
~/wan2gp-data/loras/      -> /workspace/loras
~/wan2gp-data/outputs/    -> /workspace/outputs
```

Removing or replacing the container does not delete the data in these host
directories.

## Security considerations

The container deliberately runs as root with `--privileged`, `--gpus all`, and
`--ipc=host`. The data directory is also made writable by every local user.
These settings work around GPU device-access issues seen on the intended host,
but substantially reduce container isolation. Review `deploy.sh` before use,
and only run it on a trusted single-user machine unless those permissions have
been tightened for your environment.

The UI binds to all interfaces inside the container, and Docker publishes the
host port. Do not expose port 7862 to an untrusted network without authentication
and an appropriately configured firewall or reverse proxy.

## Updating

Run the deployment command again:

```bash
./deploy.sh
```

This updates the upstream checkout, rebuilds the image, and replaces the
existing container. Checkpoints, LoRAs, and generated outputs remain in
`~/wan2gp-data`.

## Troubleshooting

### CUDA is unavailable inside the container

First verify GPU access independently of Wan2GP:

```bash
nvidia-smi
docker run --rm --gpus all ubuntu nvidia-smi
```

If the host sees the GPU but Docker does not, check the NVIDIA Container Toolkit
installation and Docker configuration. If logs report a CUDA initialization
error associated with a stuck `nvidia_uvm` module, rebooting is the safest way
to reset the driver. Advanced users can stop GPU workloads and reload the module:

```bash
docker ps -q | xargs -r docker stop
sudo modprobe -r nvidia_uvm
sudo modprobe nvidia_uvm
sudo systemctl restart docker
```

Reloading the module interrupts every process using the GPU.

### The UI does not respond on port 7862

Check the container state and logs:

```bash
docker ps -a --filter name=wan2gp-video
docker logs -f wan2gp-video
```

If the container is running, confirm the configured `HOST_PORT` and ensure the
host firewall permits that port. For access from another device, use the host's
LAN address rather than `localhost`.

### A build fails after an upstream update

The deployment patches depend on the layout of Wan2GP's upstream `Dockerfile`
and `setup.py`. Inspect the build output and the generated files in `~/Wan2GP`
if upstream changes make those patches incompatible. The build must complete
successfully before the existing container is stopped, so a build failure leaves
the previously deployed container in place.
