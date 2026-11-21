# axuz_ops/office/Dockerfile.builder — imagem de build do ONLYOFFICE Document Server (host 24.04).
#
# O QUE: base ubuntu:24.04 FIXADA POR DIGEST + pacotes do snapshot imutavel snapshot.ubuntu.com (data fixa,
#   Release assinado, apt verifica GPG). Substitui os binarios opacos: python3 (era python3.tar.gz do ONLYOFFICE-data),
#   cmake (era Kitware 3.30.0 sem hash) e o nodesource. NAO traz node, Qt, gn nem ninja: esses sao COMPILADOS do fonte
#   por stages/20-node.sh, 30-qt.sh e 40-gn-ninja.sh e ficam fora da imagem (toolchain/).
# ONDE: stages/00-image.sh (docker build). O build roda em container desta imagem com teto de 10g/6 cpus.
FROM ubuntu@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5
ENV TZ=Etc/UTC DEBIAN_FRONTEND=noninteractive DEPOT_TOOLS_METRICS=0 DEPOT_TOOLS_UPDATE=0
ARG SNAPSHOT=20261111T000000Z
RUN set -eux; \
    apt-get update -qq; apt-get install -y --no-install-recommends ca-certificates; \
    rm -f /etc/apt/sources.list.d/*; \
    printf 'deb https://snapshot.ubuntu.com/ubuntu/%s noble main universe\ndeb https://snapshot.ubuntu.com/ubuntu/%s noble-updates main universe\ndeb https://snapshot.ubuntu.com/ubuntu/%s noble-security main universe\n' "$SNAPSHOT" "$SNAPSHOT" "$SNAPSHOT" > /etc/apt/sources.list; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime; echo $TZ > /etc/timezone; \
    apt-get update -qq; \
    apt-get install -y --no-install-recommends curl git python3 python3-venv python3-pip pkg-config \
      build-essential autoconf2.13 autoconf automake libtool perl cmake gperf bison flex p7zip-full unzip xz-utils bzip2 gzip tar \
      subversion openjdk-11-jdk-headless glib-2.0-dev libglu1-mesa-dev libgtk-3-dev libpulse-dev libasound2-dev \
      libatspi2.0-dev libcups2-dev libdbus-1-dev libicu-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      libx11-xcb-dev libxcb1-dev libxcb-glx0-dev libxi-dev libxrender-dev libxss1 libncurses-dev libxkbcommon-dev \
      libxkbcommon-x11-dev libnotify-dev libvips-dev iproute2 sudo rsync; \
    rm -rf /var/lib/apt/lists/*; \
    dpkg-query -W | tr '\t' '=' | sed 's/:amd64=/=/' | sort > /etc/axuz-builder-packages.txt
