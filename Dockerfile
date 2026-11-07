# Tracker CE firmware build container
#
# Build:  docker build -t tracker-ce-build .
# Usage:  docker run --rm -v "$PWD:/src" tracker-ce-build
#         (defaults to `make all`; append any command to override, e.g.
#          ... tracker-ce-build make ptfx)
# Note: run as the image's default root user; on rootless Docker/Podman the
# generated files still map to your host user. Do NOT pass `-u $(id -u)`.

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      make \
      python3 \
      wget \
      bzip2 \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# GNU Arm Embedded Toolchain 10.3-2021.10 (matches CI and README)
ARG TOOLCHAIN_URL=https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.10/gcc-arm-none-eabi-10.3-2021.10-x86_64-linux.tar.bz2
RUN wget -q "$TOOLCHAIN_URL" -O /tmp/toolchain.tar.bz2 \
    && mkdir -p /opt/arm \
    && tar -xjf /tmp/toolchain.tar.bz2 -C /opt/arm --strip-components=1 \
    && rm /tmp/toolchain.tar.bz2
ENV PATH=/opt/arm/bin:$PATH

WORKDIR /src
CMD ["make", "all"]
