FROM ubuntu:20.04
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    flex \
    gawk \
    git \
    gperf \
    intltool \
    libexpat-dev \
    libffi-dev \
    libncurses-dev \
    meson \
    ninja-build \
    pkg-config-arm-linux-gnueabihf \
    python3-mako \
    python3-setuptools \
    texinfo \
    wget
