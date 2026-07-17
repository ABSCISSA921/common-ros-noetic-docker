FROM osrf/ros:noetic-desktop-full

USER root

# 设置环境变量，避免交互式提示
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ROS 环境配置
ENV ROBOT_TYPE=standard4
ENV ROS_IP=127.0.0.1
ENV ROS_MASTER_URI=http://localhost:11311
ENV ROSDISTRO_INDEX_URL=https://mirrors.ustc.edu.cn/rosdistro/index-v4.yaml
ENV QT_AUTO_SCREEN_SCALE_FACTOR=0
ENV QT_ENABLE_HIGHDPI_SCALING=1
ENV QT_SCALE_FACTOR=1
ENV XINIT_THREADS=1

ARG HOST_HOME_DIR=/home/hyd
ENV HOST_HOME_DIR=${HOST_HOME_DIR}

RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    # 将基础镜像的 ROS snapshot 源替换为中科大 ROS 镜像源
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros.gpg && \
    rm -f \
        /etc/apt/sources.list.d/ros1-snapshots.list \
        /etc/apt/sources.list.d/ros-latest.list && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros.gpg] https://mirrors.ustc.edu.cn/ros/ubuntu focal main" \
        > /etc/apt/sources.list.d/ros-latest.list && \
    apt-get update && \
    # 对齐当前容器在构建时执行过的系统升级
    apt-get dist-upgrade -y && \
    apt-get install -y \
        sudo \
        software-properties-common \
        wget \
        sshpass \
        openssh-server && \
    # 安装 ROS Noetic 额外常用包
    # ROS 调试工具 - rqt 全套
    apt-get install -y \
        ros-noetic-rqt-* \
        # RViz
        ros-noetic-rviz \
        ros-noetic-rviz-plugin-tutorials \
        ros-noetic-rviz-visual-tools \
        # PlotJuggler
        ros-noetic-plotjuggler \
        ros-noetic-plotjuggler-ros \
        # 功能包
        ros-noetic-robot-localization \
        ros-noetic-navigation \
        ros-noetic-slam-gmapping \
        ros-noetic-hector-mapping \
        ros-noetic-moveit \
        ros-noetic-gazebo-ros-pkgs \
        ros-noetic-ros-control \
        ros-noetic-ros-controllers \
        ros-noetic-joint-state-publisher \
        ros-noetic-xacro \
        ros-noetic-urdf \
        ros-noetic-geometry-msgs \
        ros-noetic-sensor-msgs \
        ros-noetic-nav-msgs \
        ros-noetic-tf2-ros \
        ros-noetic-tf2-geometry-msgs \
        ros-noetic-message-filters \
        ros-noetic-rosbridge-server \
        ros-noetic-joy \
        ros-noetic-teleop-twist-keyboard \
        ros-noetic-teleop-twist-joy \
        ros-noetic-imu-complementary-filter \
        ros-noetic-imu-filter-madgwick \
        ros-noetic-actionlib \
        ros-noetic-actionlib-msgs \
        ros-noetic-serial \
        ros-noetic-rosmon \
        ros-noetic-rosmon-core \
        ros-noetic-rosmon-msgs \
        ros-noetic-ethercat-grant \
        # 安装其他依赖
        python3-pip \
        python3-catkin-tools \
        python3-rosdep \
        python3-rosinstall \
        python3-rosinstall-generator \
        python3-wstool \
        build-essential \
        cmake \
        git \
        vim \
        jq \
        libserial-dev \
        iproute2 && \
    mkdir -p /etc/apt/keyrings /tmp/rosdep && \
    chmod 755 /etc/apt/keyrings /tmp/rosdep && \
    chown nobody:nogroup /tmp/rosdep && \
    # 安装 clangd-21 及 LLVM 21 开发库（从 LLVM 源）
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg && \
    echo 'deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/focal/ llvm-toolchain-focal-21 main' > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y clangd-21 llvm-21-dev && \
    apt-get install -y clang-format && \
    ln -sf /usr/bin/clangd-21 /usr/local/bin/clangd && \
    # 使用中科大 rosdistro 镜像初始化 rosdep
    mkdir -p /etc/ros/rosdep/sources.list.d && \
    curl -fsSL \
        https://mirrors.ustc.edu.cn/rosdistro/rosdep/sources.list.d/20-default.list \
        -o /etc/ros/rosdep/sources.list.d/20-default.list && \
    sed -i \
        's#raw.githubusercontent.com/ros/rosdistro/master#mirrors.ustc.edu.cn/rosdistro#g' \
        /etc/ros/rosdep/sources.list.d/20-default.list && \
    rosdep fix-permissions && \
    sudo -u nobody env \
        HOME=/tmp/rosdep \
        ROSDISTRO_INDEX_URL=${ROSDISTRO_INDEX_URL} \
        rosdep update && \
    # 清理
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 配置颜色化 bash 和 ROS 环境变量
RUN echo '# 颜色化 bash' >> /root/.bashrc && \
    echo 'export TERM=xterm-256color' >> /root/.bashrc && \
    echo "alias ls='ls --color=auto'" >> /root/.bashrc && \
    echo "alias grep='grep --color=auto'" >> /root/.bashrc && \
    echo "alias ll='ls -alF --color=auto'" >> /root/.bashrc && \
    echo "alias pl='rosrun plotjuggler plotjuggler'" >> /root/.bashrc && \
    echo "alias rp='rosrun plotjuggler plotjuggler'" >> /root/.bashrc && \
    echo "alias sd='source devel/setup.bash'" >> /root/.bashrc && \
    echo "alias openbash='vim ~/.bashrc'" >> /root/.bashrc && \
    echo "alias wired='sshpass -p dynamicx ssh dynamicx@192.168.100.2'" >> /root/.bashrc && \
    echo "alias mlhw='mon launch rm_config rm_ecat_hw.launch'" >> /root/.bashrc && \
    echo "alias mllc='mon launch rm_config load_controllers.launch'" >> /root/.bashrc && \
    echo 'PS1="${debian_chroot:+($debian_chroot)}\[\\033[01;32m\]\u@\h\[\\033[00m\]:\[\\033[01;34m\]\w\[\\033[00m\]\$ "' >> /root/.bashrc && \
    echo '' >> /root/.bashrc && \
    echo '# ROS 环境配置' >> /root/.bashrc && \
    echo 'source /opt/ros/noetic/setup.bash' >> /root/.bashrc && \
    echo 'export ROBOT_TYPE=standard4' >> /root/.bashrc && \
    echo '[ ! -f devel/setup.bash ] || source devel/setup.bash' >> /root/.bashrc
WORKDIR ${HOST_HOME_DIR}
LABEL org.opencontainers.image.source=https://github.com/HydrogenZp/common-ros-noetic-docker
LABEL org.opencontainers.image.description="Common ROS Noetic Docker Image with pre-configured tools"
LABEL org.opencontainers.image.licenses=MIT
