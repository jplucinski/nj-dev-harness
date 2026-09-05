# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

ARG TASK_VERSION=3.52.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      fzf \
      git \
      less \
      ripgrep \
      tar \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) task_arch=amd64 ;; \
      arm64) task_arch=arm64 ;; \
      *) printf 'Unsupported architecture\n' >&2; exit 1 ;; \
    esac; \
    asset="task_linux_${task_arch}.tar.gz"; \
    release_url="https://github.com/go-task/task/releases/download/v${TASK_VERSION}"; \
    curl -fsSLo "/tmp/$asset" "$release_url/$asset"; \
    curl -fsSLo /tmp/task_checksums.txt "$release_url/task_checksums.txt"; \
    grep -E "^[0-9a-f]{64}[[:space:]]+$asset$" /tmp/task_checksums.txt > /tmp/task.sha256; \
    (cd /tmp && sha256sum -c task.sha256); \
    tar -xzf "/tmp/$asset" -C /usr/local/bin task; \
    rm -f "/tmp/$asset" /tmp/task_checksums.txt /tmp/task.sha256; \
    task --version

RUN useradd --create-home --shell /bin/bash demo

WORKDIR /opt/dev-harness-source
COPY VERSION README.md CHANGELOG.md LICENSE install.sh install.ps1 Taskfile.global.yml ./
COPY config ./config
COPY scripts ./scripts
COPY shell ./shell
COPY demo ./demo
RUN chown -R demo:demo /opt/dev-harness-source \
    && chmod +x /opt/dev-harness-source/demo/entrypoint.sh

USER demo
ENV HOME=/home/demo \
    DEV_WORKPLACE=/home/demo/Workplace \
    DEV_EDITOR=less \
    TERM=xterm-256color

RUN ./install.sh --configure-shell \
    && sed -i 's|^export DEV_EDITOR=.*|export DEV_EDITOR="less"|' "$HOME/.config/dev-harness/config.env" \
    && bash ./demo/entrypoint.sh --prepare-only

WORKDIR /home/demo
ENTRYPOINT ["bash", "/opt/dev-harness-source/demo/entrypoint.sh"]
