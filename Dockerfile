# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-ubuntu:jammy

# set version label
ARG BUILD_DATE
ARG KASM_VERSION
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Env
ENV DOCKER_TLS_CERTDIR=""
ENV TINI_SUBREAPER=true

#Add needed nvidia environment variables for https://github.com/NVIDIA/nvidia-docker
ENV NVIDIA_DRIVER_CAPABILITIES="compute,graphics,video,utility" \
    VERSION="develop"

# Container setup
RUN \
  echo "**** install packages ****" && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
  echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu jammy stable" > \
    /etc/apt/sources.list.d/docker.list && \
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg && \
  curl -s -L https://nvidia.github.io/libnvidia-container/ubuntu22.04/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list && \
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
  apt-get install -y --no-install-recommends \
    btrfs-progs \
    containerd.io \
    docker-ce \
    docker-ce-cli \
    e2fsprogs \
    fuse-overlayfs \
    g++ \
    gcc \
    iproute2 \
    iptables \
    jq \
    lsof \
    make \
    nodejs \
    nvidia-container-toolkit \
    nvidia-docker2 \
    openssl \
    pigz \
    python3 \
    sudo \
    uidmap \
    xfsprogs && \
  echo "**** compose install ****" && \
  mkdir -p /usr/local/lib/docker/cli-plugins && \
  curl -L \
    https://github.com/docker/compose/releases/download/v2.5.0/docker-compose-$(uname -s)-$(uname -m) -o \
    /usr/local/lib/docker/cli-plugins/docker-compose && \
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
  echo "**** dind setup ****" && \
  useradd -U dockremap && \
  usermod -G dockremap dockremap && \
  echo 'dockremap:165536:65536' >> /etc/subuid && \
  echo 'dockremap:165536:65536' >> /etc/subgid && \
  curl -o \
  /usr/local/bin/dind -L \
    https://raw.githubusercontent.com/moby/moby/master/hack/dind && \
  chmod +x /usr/local/bin/dind && \
  echo 'hosts: files dns' > /etc/nsswitch.conf && \
  echo "**** setup wizard ****" && \
  mkdir -p /wizard && \
  if [ -z ${KASM_VERSION+x} ]; then \
      KASM_VERSION=$(curl -sX GET 'https://api.github.com/repos/kasmtech/kasm-install-wizard/releases/latest' \
      | jq -r '.name'); \
  fi && \
  echo "${KASM_VERSION}" > /version.txt && \
  curl -o \
    /tmp/wizard.tar.gz -L \
    "https://github.com/kasmtech/kasm-install-wizard/archive/refs/tags/${KASM_VERSION}.tar.gz" && \
  tar xf \
    /tmp/wizard.tar.gz -C \
    /wizard --strip-components=1 && \
  cd /wizard && \
  npm install && \
  echo "**** add installer ****" && \
  curl -o \
    /tmp/kasm.tar.gz -L \
    "https://kasmweb-build-artifacts.s3.amazonaws.com/kasm_backend/b05ebcfbd973739debca5bc2d91b6ac1e01fcdc7/kasm_workspaces_1.16.0_1.16.0.b05ebc.tar.gz" && \
  tar xf \
    /tmp/kasm.tar.gz -C \
    / && \
  ALVERSION=$(cat /kasm_release/conf/database/seed_data/default_properties.yaml |awk '/alembic_version/ {print $2}') && \
  curl -o \
    /tmp/images.tar.gz -L \
    "https://kasm-ci.s3.amazonaws.com/1.16.0-images-combined.tar.gz" && \
  tar xf \
    /tmp/images.tar.gz -C \
    / && \
  sed -i \
    '/alembic_version/s/.*/alembic_version: '${ALVERSION}'/' \
    /kasm_release/conf/database/seed_data/default_images_a* && \
  sed -i 's/-N -e -H/-N -B -e -H/g' /kasm_release/upgrade.sh && \
  echo "exit 0" > /kasm_release/install_dependencies.sh && \
  /kasm_release/bin/utils/yq_$(uname -m) -i \
    '.services.proxy.volumes += "/kasm_release/www/img/thumbnails:/srv/www/img/thumbnails"' \
    /kasm_release/docker/docker-compose-all.yaml && \
  echo "**** copy assets ****" && \
  cp \
    /kasm_release/www/img/thumbnails/*.png /kasm_release/www/img/thumbnails/*.svg \
    /wizard/public/img/thumbnails/ && \
  cp \
    /kasm_release/conf/database/seed_data/default_images_a* \
    /wizard/ && \
  echo "**** cleanup ****" && \
  apt-get remove -y g++ gcc make && \
  apt-get -y autoremove && \
  apt-get clean && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/*

# add init files
COPY root/ /

# Ports and volumes
EXPOSE 3000 443
VOLUME /opt/
