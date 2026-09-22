# Common ROS Noetic Docker

基于 Docker 的 ROS Noetic 开发环境，预配置了常用工具与依赖。

## 项目简介

本项目提供一个容器化的 ROS Noetic 开发环境，预装了常用的 ROS 功能包、调试工具和开发 utilities。

> **其他语言**: [English](README.md)

> 默认使用 `.env` 中的 `HOST_HOME_DIR` 作为容器工作目录和主目录挂载路径，避免硬编码用户名。

## 主要特性

- **基础镜像**: OSRF ROS Noetic desktop full
- **开发工具**: catkin_tools、rosinstall、wstool、build-essential、cmake、GitHub CLI、Node.js 24
- **调试工具**: rqt 套件、RViz、PlotJuggler
- **导航与 SLAM**: navigation 导航栈、gmapping、hector_mapping、robot_localization
- **运动规划**: MoveIt
- **仿真环境**: Gazebo、ros_control、UPatras Gazebo 插件
- **通信工具**: rosbridge_server、tf2、actionlib
- **硬件接口**: serial、joy、teleop 系列包
- **数据处理**: sensor_msgs、geometry_msgs、nav_msgs、message_filters

## 快速开始

### 构建镜像

```bash
docker compose build
```

> 本项目统一使用 Docker Compose v2 插件命令 `docker compose`。旧版独立命令 `docker-compose` 无需安装，并且在新环境中可能不存在。

首次使用请先在项目根目录 `.env` 中设置：

```bash
HOST_HOME_DIR=/home/你的用户名
```

### 启动容器

```bash
docker compose up -d
```

> Dev Container 启动加速提示：
> 本项目通过 Docker 命名卷持久化 `/root/.vscode-server`，因此 VS Code Server 和远程扩展数据会在重建容器后复用。
> 首次连接可能仍较慢（下载 + 解压），后续连接会明显更快。

### 进入容器

```bash
docker exec -it ros1_noetic_dev bash
```

## 配置说明

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `ROS_IP` | `127.0.0.1` | ROS 网络接口地址 |
| `ROS_MASTER_URI` | `http://localhost:11311` | ROS 主节点 URI |
| `DISPLAY` | - | X11 显示，用于 GUI 应用 |
| `HOST_HOME_DIR` | `/home/hyd` | 宿主用户目录（同时用于构建参数、容器工作目录和卷映射） |

### 卷映射

- `/tmp/.X11-unix`: X11 套接字，支持图形界面应用
- `${HOST_HOME_DIR}:${HOST_HOME_DIR}`: 用户主目录映射
- `vscode-server-data:/root/.vscode-server`: 持久化 VS Code Server 二进制与远程用户数据
- `vscode-extensions:/root/.vscode/extensions`: 持久化附加扩展缓存

### Dev Container 二次连接加速建议（推荐）

1. 保持相同的 Compose 项目名（默认就是目录名），确保命名卷可复用。
2. 非必要不要执行 `down -v`，否则会清空缓存卷。
3. 需要重建镜像时，优先只重建镜像，不删除卷。

如果首次连接仍慢，通常是 VS Code Server 首次下载阶段受网络带宽影响。

## 无独显主机：让容器使用 Intel 核显

ROS Noetic 镜像基于 Ubuntu 20.04。对于较新的 Intel 处理器，即使
`/dev/dri` 已经正确映射进容器，镜像内较旧的 Mesa 用户态驱动仍可能无法识别
核显，最终回退到使用 CPU 的 `llvmpipe`。本方案已在 Arrow Lake-P
（PCI ID `8086:7d51`）上验证：Mesa 21.2.6 会报告不支持该 PCI ID，升级到
Mesa 25.0.7 后可通过 `iris` 驱动直接使用 Intel 核显。

### 1. 先检查宿主机

宿主机必须已经有可用的 Intel 内核驱动和 render 节点：

```bash
lspci -nnk | grep -A4 -Ei 'VGA|3D|Display'
ls -l /dev/dri
```

正常情况下应看到 `Kernel driver in use: i915`（较新的配置也可能是 `xe`），
并存在 `/dev/dri/renderD128` 一类设备。如果宿主机没有 render 节点，应先修复
宿主机驱动；容器无法替代宿主机的内核驱动。

允许容器所使用的本地 root 用户访问当前 X11 会话：

```bash
xhost +SI:localuser:root
```

这比完全关闭 X11 访问控制的 `xhost +` 范围更小。

### 2. 映射 Intel GPU，并取消强制软件渲染

在 `docker-compose.yml` 中保留：

```yaml
services:
  ros1:
    devices:
      - /dev/dri:/dev/dri
    environment:
      - DISPLAY=${DISPLAY}
      - QT_X11_NO_MITSHM=1
```

如果存在 `LIBGL_ALWAYS_SOFTWARE=1`，应将其删除。无 NVIDIA 独显的机器还应
删除 NVIDIA 专用环境变量，以及 Compose 中 `driver: nvidia` 的设备预留配置。

本项目默认以 root 用户运行容器，因此可以访问映射后的 render 节点。如果以后
改为非 root 用户运行，需要让该用户加入与宿主机 `render` 组数字 GID 相同的
容器用户组。

### 3. 安装能够识别新核显的 Mesa

Ubuntu 20.04 默认的 Mesa 21 对较新的 Intel PCI ID 支持不足。在 Dockerfile
末尾、`WORKDIR` 之前加入以下层：

```dockerfile
# Ubuntu 20.04 的 Mesa 21 早于新款 Intel 核显。
# 使用面向 Focal 的稳定 Mesa 回移包，让 GUI 应用访问 /dev/dri。
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

这里使用 [Kisak Mesa stable PPA](https://launchpad.net/~kisak/+archive/ubuntu/turtle)。
它是第三方 Launchpad 软件源，提供为 Ubuntu 20.04 构建的新版 Mesa。若用于
生产环境或要求完全可复现的构建，应审查并固定具体软件包版本。已经被 Focal
默认 Mesa 支持的较老 Intel 核显通常不需要增加这个软件源。

### 4. 重新构建并重建容器

请在图形桌面的终端中执行，以确保 `DISPLAY` 已设置：

```bash
docker compose build ros1
docker compose up -d --force-recreate ros1
```

重建容器不会删除 `${HOST_HOME_DIR}` 宿主机目录映射和 VS Code 命名卷。除非
明确要删除这些缓存，否则不要执行带 `-v` 的 `docker compose down`。

### 5. 验证是否真正使用 Intel GPU

```bash
docker exec ros1_noetic_dev glxinfo -B | \
  grep -E 'direct rendering|Vendor:|Device:|Accelerated:|OpenGL renderer|OpenGL core profile version'
```

正常结果类似：

```text
direct rendering: Yes
Vendor: Intel (0x8086)
Device: Mesa Intel(R) Graphics (ARL)
Accelerated: yes
OpenGL renderer string: Mesa Intel(R) Graphics (ARL)
OpenGL core profile version string: 4.6 ... Mesa 25.0.7
```

如果看到 `llvmpipe`、`softpipe` 或 `Accelerated: no`，说明仍在使用 CPU 软件
渲染。可以打开驱动加载日志继续定位：

```bash
docker exec -e LIBGL_DEBUG=verbose ros1_noetic_dev glxinfo -B
```

同时确认运行中的容器没有残留软件渲染开关：

```bash
docker inspect ros1_noetic_dev --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep LIBGL_ALWAYS_SOFTWARE
```

正常情况下该命令没有输出。`glxinfo` 显示 Intel 渲染器后，RViz、PlotJuggler、
Gazebo 等 X11/OpenGL 图形程序即可正常调用核显。

### 常见问题与回退方法

- 出现 `Error: unable to open display`：在当前图形会话执行前面的 `xhost` 命令，
  并确认容器的 `DISPLAY` 与宿主机一致。
- 容器内没有 `/dev/dri`：检查 Compose 的 `devices` 映射，然后重建容器。
- 访问 `renderD*` 时出现 `Permission denied`：将非 root 容器用户加入与宿主机
  render 节点数字 GID 相同的组。
- 出现 `Driver does not support the ... PCI ID`：容器仍在使用旧 Mesa；检查
  `libgl1-mesa-dri` 的版本，必要时清理对应构建层后重新构建。
- 如需临时回退到 CPU 渲染，可设置 `LIBGL_ALWAYS_SOFTWARE=1`；再次测试 Intel
  GPU 前必须删除该变量。

## 可用工具

### ROS 调试工具
- `rqt-*` - 完整的 rqt 插件套件
- `rviz` - 3D 可视化工具
- `plotjuggler` - 时序数据可视化工具

### 导航与建图
- `robot_localization` - 多传感器状态估计
- `navigation` - 导航功能栈
- `slam_gmapping` - 栅格地图 SLAM
- `hector_mapping` - Hector SLAM 算法

### 机器人控制
- `moveit` - 运动规划框架
- `gazebo_ros_pkgs` - 机器人仿真环境
- `ros_control` - 机器人控制框架

## 依赖要求

- Docker Engine
- Docker Compose v2 插件（`docker compose version`）
- X11 服务器（用于图形界面应用）

## 许可证

MIT License

## 致谢

- [OSRF](https://www.osrfoundation.org/) - ROS Noetic 基础镜像
- [ROS](https://www.ros.org/) - 机器人操作系统
