# syntax=docker/dockerfile:1
#
# Home Assistant add-on: Paseo
#
# Built FROM the upstream Paseo image rather than a Home Assistant base image.
# Upstream is Debian bookworm + Node 22 and already ships bash, curl, git,
# gosu, tini, openssh-client and procps, so this layer only adds the agent
# CLIs, the Home Assistant tooling, and the Supervisor glue.

# Overridden by build.yaml's build_from under the Home Assistant builder. Kept in
# step with it by .github/workflows/upstream-release.yaml, which matches on the
# `<version> -> sha256:<digest>` shape of the comment below.
# 0.7.2 -> sha256:da9286410d9dd86208755b789894534d9e200c9021bd45157557aac4146b84fb
ARG BUILD_FROM=ghcr.io/getpaseo/paseo:0.7.2
FROM ${BUILD_FROM}

ARG BUILD_ARCH=amd64
ARG BUILD_VERSION=dev
ARG HA_CLI_VERSION=5.4.0
ARG GH_CLI_VERSION=2.98.0

# Agent CLI versions are pinned so a rebuild of a given add-on version always
# produces the same image. Unpinned `npm install -g` would silently ship
# whatever happened to be latest on build day, which makes "0.3.1-1" mean
# different things on different days. Bumped deliberately; see DOCS.md,
# "Keeping things up to date". The check-updates workflow files an issue when
# any of these fall behind.
ARG CLAUDE_CODE_VERSION=2.1.251
ARG CODEX_VERSION=0.151.0
ARG OPENCODE_VERSION=1.18.25
ARG COPILOT_VERSION=1.0.82
ARG GEMINI_CLI_VERSION=0.57.0

# Upstream's entrypoint owns the privilege drop to uid 1000, so this image
# must stay root at the end. See the Docker page of the Paseo docs.
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# OS packages. bash/curl/git/gosu/tini/openssh-client/procps come from upstream.
#
# The YAML tooling earns its place: this add-on's whole job is agents editing
# Home Assistant config. python3-yaml (PyYAML) is the baseline `import yaml`;
# python3-ruamel.yaml round-trips comments and formatting so an in-place edit of
# configuration.yaml does not flatten a hand-written file; yamllint catches the
# exact traps the agent guide warns about (unquoted on/off, indentation); and
# moreutils brings `sponge`, which replaces the read-tmp-mv dance for pipe edits.
# Installed via apt, not pip, because the system Python is externally managed and
# these all ship as Debian packages.
#
# JSON is the other half of the same job. jq (already present) queries JSON; yq
# applies jq syntax to YAML and converts between the two, so an HA config can be
# filtered or reshaped in place; jo builds JSON payloads from shell args, which
# is exactly what `hass-api POST` wants.
#
# Network utilities are for diagnosing why the agent can't reach something -- HA
# Core, an MCP server, a webhook target. Upstream already ships curl; this adds
# DNS (bind9-dnsutils: dig, nslookup), reachability (iputils-ping), port probing
# (netcat-openbsd: nc), path tracing (traceroute) and socket/route inspection
# (iproute2: ss, ip).
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        acl \
        bind9-dnsutils \
        ca-certificates \
        iproute2 \
        iputils-ping \
        jo \
        jq \
        less \
        moreutils \
        nano \
        netcat-openbsd \
        python3 \
        python3-ruamel.yaml \
        python3-venv \
        python3-yaml \
        rsync \
        ripgrep \
        traceroute \
        unzip \
        yamllint \
        yq \
        bash-completion \
        fzf \
        tree \
        htop; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Home Assistant CLI and GitHub CLI, selected from the Supervisor build arch.
# home-assistant/cli publishes assets named exactly ha_amd64 / ha_aarch64.
# ---------------------------------------------------------------------------
RUN set -eux; \
    case "${BUILD_ARCH}" in \
        amd64)   ha_asset="ha_amd64";   gh_arch="amd64" ;; \
        aarch64) ha_asset="ha_aarch64"; gh_arch="arm64" ;; \
        *) echo "unsupported BUILD_ARCH: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${HA_CLI_VERSION}/${ha_asset}"; \
    chmod +x /usr/local/bin/ha; \
    curl -fsSL -o /tmp/gh.deb \
        "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${gh_arch}.deb"; \
    dpkg -i /tmp/gh.deb; \
    rm -f /tmp/gh.deb; \
    ha --help >/dev/null; \
    gh --version

# ---------------------------------------------------------------------------
# Agent CLIs.
#
# ORDER IS LOAD-BEARING: this must run BEFORE NPM_CONFIG_PREFIX is repointed at
# /data below. /data is a Supervisor-managed bind mount at runtime, so anything
# installed there at build time is masked and effectively vanishes on start.
# These land in /usr/local and are owned by the image, not by add-on state.
# ---------------------------------------------------------------------------
RUN set -eux; \
    npm install -g --no-fund --no-audit \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@github/copilot@${COPILOT_VERSION}" \
        "@google/gemini-cli@${GEMINI_CLI_VERSION}"; \
    npm cache clean --force; \
    claude --version; \
    codex --version; \
    opencode --version; \
    gemini --version

# ---------------------------------------------------------------------------
# Relocate every mutable state path off the anonymous /home/paseo volume.
#
# The upstream image declares VOLUME /home/paseo. Supervisor does not bind that
# path, so Docker creates an anonymous volume for it that is discarded whenever
# the add-on is updated or rebuilt. Every one of these paths is env-driven
# upstream, so pointing them at /data (persistent and included in Supervisor
# backups) is enough to survive updates without patching anything.
# ---------------------------------------------------------------------------
# node-pty spawns $SHELL and falls back to /bin/sh when it is unset -- which on
# Debian is dash: no tab completion, no readline config, and it never reads
# .bashrc. Terminal panes were getting that rather than bash.
ENV SHELL=/bin/bash

ENV HOME=/data/home \
    PASEO_HOME=/data/home/.paseo \
    CLAUDE_CONFIG_DIR=/data/home/.claude \
    CODEX_HOME=/data/home/.codex \
    XDG_CONFIG_HOME=/data/home/.config \
    XDG_DATA_HOME=/data/home/.local/share \
    XDG_STATE_HOME=/data/home/.local/state \
    XDG_CACHE_HOME=/data/home/.cache \
    NPM_CONFIG_PREFIX=/data/home/.npm-global \
    NPM_CONFIG_CACHE=/data/home/.cache/npm \
    GIT_CONFIG_GLOBAL=/data/home/.gitconfig \
    PATH=/run/ha-paseo/shims:/share/paseo/bin:/data/home/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# gosu -- used both by the upstream entrypoint and by this add-on -- derives
# $HOME from /etc/passwd and re-exports it, which drags child processes back to
# /home/paseo even though every explicit variable above points at /data. Move
# the account's home directory so passwd agrees with the environment; without
# this, agent credentials land on the throwaway volume.
RUN usermod --home /data/home paseo

# The npm layer above ran while the base image's HOME was still /home/paseo, so
# npm left .npm/.cache/.config/.local (and codex left .codex) behind there.
# Docker seeds the anonymous volume from whatever is in the image at this path,
# so leaving them would resurrect a phantom home on every start. Empty it.
RUN rm -rf /home/paseo/..?* /home/paseo/.[!.]* /home/paseo/*

COPY rootfs/ /
RUN chmod +x /usr/local/sbin/ha \
             /usr/local/bin/ha-paseo-entrypoint \
             /usr/local/bin/ha-paseo-seed-config \
             /usr/local/bin/ha-paseo-postboot \
             /usr/local/bin/hass-api \
             /usr/local/bin/ha-inventory \
             /usr/local/bin/update-agents \
             /usr/local/bin/agent-login \
             /usr/local/bin/ha-paseo-services \
             /usr/local/bin/ha-paseo-shims \
             /usr/local/bin/ha-paseo-doctor

# The add-on version no longer encodes Paseo's, so the daemon version has to be
# recorded somewhere a running container can report it -- `ha-paseo-doctor` reads
# this. Taken from the installed package rather than from BUILD_FROM, so it states
# what is actually in the image even if the pin and the tag ever disagree.
RUN set -eux; \
    paseo_version="$(jq -r '.version // "unknown"' \
        /usr/local/lib/node_modules/@getpaseo/cli/package.json)"; \
    printf '{"version":"%s","paseo":"%s"}\n' "${BUILD_VERSION}" "$paseo_version" \
        > /etc/ha-paseo-release; \
    cat /etc/ha-paseo-release

LABEL \
    io.hass.name="Paseo" \
    io.hass.description="Self-hosted orchestration for Claude Code, Codex and OpenCode, with Home Assistant access" \
    io.hass.type="addon" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/danielcbaldwin/ha-paseo"

# Upstream's HEALTHCHECK (GET /api/health, the one route that skips auth) is
# inherited as-is.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/ha-paseo-entrypoint"]
