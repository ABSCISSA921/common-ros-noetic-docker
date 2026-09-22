# Common ROS Noetic Docker
frok from HydrogenZp(https://github.com/HydrogenZp/common-ros-noetic-docker)，Some dependencies have been added based on this.

A Docker-based development environment for ROS Noetic with pre-configured tools and dependencies.

## Overview

This project provides a containerized ROS Noetic development environment with commonly used packages, debugging tools, and development utilities pre-installed.

> **Other Languages**: [简体中文](README_zh.md)

> By default, this project uses `HOST_HOME_DIR` from `.env` for both container working directory and home volume mapping, so usernames are not hardcoded.

## Features

- **Base Image**: OSRF ROS Noetic desktop full
- **Development Tools**: catkin_tools, rosinstall, wstool, build-essential, cmake, GitHub CLI, Node.js 24
- **Debugging Tools**: rqt suite, RViz, PlotJuggler
- **Navigation & SLAM**: navigation stack, gmapping, hector_mapping, robot_localization
- **Motion Planning**: MoveIt
- **Simulation**: Gazebo, ros_control, UPatras Gazebo plugins
- **Communication**: rosbridge_server, tf2, actionlib
- **Hardware Interface**: serial, joy, teleop packages
- **Data Processing**: sensor_msgs, geometry_msgs, nav_msgs, message_filters

## Quick Start

### Build the Image

```bash
docker compose build
```

> This project uses the Docker Compose v2 plugin command `docker compose`. The legacy standalone `docker-compose` command is not required and may not exist on newer systems.

Before first use, set this in `.env` at the project root:

```bash
HOST_HOME_DIR=/home/your-username
```

### Run the Container

```bash
docker compose up -d
```

> Dev Container startup speed tip:
> this project persists `/root/.vscode-server` via Docker named volumes, so VS Code Server and remote extension data are reused across container recreations.
> First attach may still be slow (download + extract), while subsequent attaches are much faster.

### Access the Container

```bash
docker exec -it ros1_noetic_dev bash
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ROS_IP` | `127.0.0.1` | ROS network interface |
| `ROS_MASTER_URI` | `http://localhost:11311` | ROS master URI |
| `DISPLAY` | - | X11 display for GUI applications |
| `HOST_HOME_DIR` | `/home/hyd` | Host user directory (used for build arg, container workdir, and volume mapping) |

### Volumes

- `/tmp/.X11-unix`: X11 socket for GUI support
- `${HOST_HOME_DIR}:${HOST_HOME_DIR}`: User home directory mapping
- `vscode-server-data:/root/.vscode-server`: persist VS Code Server binaries and remote user data
- `vscode-extensions:/root/.vscode/extensions`: persist additional extension cache

### Faster Dev Container Reopen (recommended)

1. Keep using the same Docker Compose project name (default is folder name), so named volumes are reused.
2. Avoid `down -v` unless you intentionally want to clear caches.
3. If you need to rebuild image, prefer rebuild without deleting volumes.

If startup is still slow on first run, it's usually network-bound while downloading VS Code Server.

## Intel iGPU Acceleration Without a Discrete GPU

ROS Noetic images are based on Ubuntu 20.04. On recent Intel processors, the
kernel device can be passed into the container correctly while the old Mesa
userspace driver in the image still falls back to `llvmpipe`. This was verified
on an Arrow Lake-P GPU (`8086:7d51`): Mesa 21.2.6 reported that the PCI ID was
unsupported, while Mesa 25.0.7 provided direct hardware rendering through the
`iris` driver.

### 1. Check the host first

The host must already have a working Intel kernel driver and a render node:

```bash
lspci -nnk | grep -A4 -Ei 'VGA|3D|Display'
ls -l /dev/dri
```

Expected results include `Kernel driver in use: i915` (or `xe` on a newer
setup) and a device such as `/dev/dri/renderD128`. Fix the host driver first if
the render node does not exist; a container cannot provide the host kernel
driver.

Allow only the local root user used by this container to connect to the current
X11 session:

```bash
xhost +SI:localuser:root
```

### 2. Pass the Intel GPU and do not force software rendering

Keep the following in `docker-compose.yml`:

```yaml
services:
  ros1:
    devices:
      - /dev/dri:/dev/dri
    environment:
      - DISPLAY=${DISPLAY}
      - QT_X11_NO_MITSHM=1
```

Remove `LIBGL_ALWAYS_SOFTWARE=1` if it is present. On a machine without an
NVIDIA GPU, also remove NVIDIA-only environment entries and any Compose device
reservation whose driver is `nvidia`.

The default container user is `root`, so it can open the mapped render node. If
the image is changed to run as a non-root user, add that user to a container
group whose numeric GID matches the host `render` group.

### 3. Install a Mesa version that supports the GPU

The Ubuntu 20.04 Mesa 21 stack is too old for recent Intel PCI IDs. Add this
layer near the end of the `Dockerfile`, before `WORKDIR`:

```dockerfile
# Mesa 21 from Ubuntu 20.04 predates recent Intel integrated GPUs.
# Use the stable Focal Mesa backport so GUI applications can use /dev/dri.
RUN add-apt-repository -y ppa:kisak/turtle && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libdrm2 \
        libegl-mesa0 \
        libgbm1 \
        libgl1-mesa-dri \
        libglx-mesa0 \
        mesa-utils && \
    rm -rf /var/lib/apt/lists/*
```

This uses the [Kisak Mesa stable PPA](https://launchpad.net/~kisak/+archive/ubuntu/turtle),
a third-party Launchpad archive that provides newer Mesa packages built for
Ubuntu 20.04. Review and pin the packages if the image is used in a production
or reproducible-build environment. Older Intel GPUs already supported by the
standard Focal Mesa packages may not need this layer.

### 4. Rebuild and recreate the container

Run these commands from a graphical terminal so `DISPLAY` is available:

```bash
docker compose build ros1
docker compose up -d --force-recreate ros1
```

Named VS Code volumes and the `${HOST_HOME_DIR}` bind mount survive this
container recreation. Do not add `-v` to `docker compose down` unless those
volumes should be deleted intentionally.

### 5. Verify hardware rendering

```bash
docker exec ros1_noetic_dev glxinfo -B | \
  grep -E 'direct rendering|Vendor:|Device:|Accelerated:|OpenGL renderer|OpenGL core profile version'
```

A working Intel path looks similar to:

```text
direct rendering: Yes
Vendor: Intel (0x8086)
Device: Mesa Intel(R) Graphics (ARL)
Accelerated: yes
OpenGL renderer string: Mesa Intel(R) Graphics (ARL)
OpenGL core profile version string: 4.6 ... Mesa 25.0.7
```

`llvmpipe`, `softpipe`, or `Accelerated: no` means the container is still using
the CPU. Use the verbose loader output to find the reason:

```bash
docker exec -e LIBGL_DEBUG=verbose ros1_noetic_dev glxinfo -B
```

Also check that the running container did not retain a software override:

```bash
docker inspect ros1_noetic_dev --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep LIBGL_ALWAYS_SOFTWARE
```

No output is expected. After `glxinfo` reports the Intel renderer, RViz,
PlotJuggler, Gazebo, and other X11/OpenGL applications can use the integrated
GPU normally.

### Troubleshooting and fallback

- `Error: unable to open display`: run the `xhost` command above in the active
  graphical session and ensure the container's `DISPLAY` matches the host.
- `/dev/dri` is missing in the container: check the Compose `devices` mapping
  and recreate the container.
- `Permission denied` on `renderD*`: align the non-root container user's group
  with the host render-node GID.
- `Driver does not support the ... PCI ID`: the image is still using the old
  Mesa driver; verify the installed `libgl1-mesa-dri` version and rebuild
  without stale layers if necessary.
- For a temporary CPU-rendering fallback, set `LIBGL_ALWAYS_SOFTWARE=1`. Remove
  it again before testing the Intel GPU.

## Available Tools

### ROS Debugging
- `rqt-*` - Complete rqt plugin suite
- `rviz` - 3D visualization
- `plotjuggler` - Time series data visualization

### Navigation & Mapping
- `robot_localization` - Multi-sensor state estimation
- `navigation` - Navigation stack
- `slam_gmapping` - Grid-based SLAM
- `hector_mapping` - Hector SLAM

### Robot Control
- `moveit` - Motion planning framework
- `gazebo_ros_pkgs` - Robot simulation
- `ros_control` - Robot control framework

## Dependencies

- Docker Engine
- Docker Compose v2 plugin (`docker compose version`)
- X11 server (for GUI applications)

## License

MIT License

## Acknowledgments

- [OSRF](https://www.osrfoundation.org/) - ROS Noetic base image
- [ROS](https://www.ros.org/) - Robot Operating System
