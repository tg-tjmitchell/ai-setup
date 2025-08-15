#!/usr/bin/env bash
set -euo pipefail

# Minimal standalone installer for ComfyUI logic extracted from the project's Dockerfile.
# - Installs comfy-cli (and jupyterlab)
# - Optionally attempts to install cloudflared (only if apt-get is available)
# - Runs `comfy install` with optional NVIDIA support via ADD_NVIDIA env var
# - Installs custom nodes listed in the first row of plugins.csv (comma-separated)
# - Creates expected config directories and copies config.ini if present
# - Resets the models directory

# Configuration (override via env vars)
ADD_NVIDIA=${ADD_NVIDIA:-true}
COMFY_ROOT=${COMFY_ROOT:-"$HOME/comfy/ComfyUI"}
PLUGINS_CSV=${PLUGINS_CSV:-"./plugins.csv"}
CONFIG_INI=${CONFIG_INI:-"./config.ini"}

echo "ComfyUI installer (standalone)"
echo "COMFY_ROOT=${COMFY_ROOT} ADD_NVIDIA=${ADD_NVIDIA}"

# Ensure pip and comfy-cli
echo "Upgrading pip and installing comfy-cli"
python -m pip install --upgrade pip
python -m pip install --no-cache-dir comfy-cli
# Optional cloudflared installation: only if apt-get is available (best-effort)
if command -v apt-get >/dev/null 2>&1; then
  echo "Attempting cloudflared install (apt-based)"
  tmpdeb=$(mktemp --suffix=.deb)
  if curl -fsSL -o "$tmpdeb" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb; then
    set +e
    sudo apt-get update && sudo apt-get install -y "$tmpdeb" || (sudo dpkg -i "$tmpdeb" && sudo apt-get install -f -y)
    set -e
    rm -f "$tmpdeb"
  else
    echo "Could not download cloudflared; skipping"
    rm -f "$tmpdeb" || true
  fi
else
  echo "apt-get not found; skipping cloudflared install"
fi

# Run comfy install
echo "Running comfy install (fast-deps)"
if [[ "${ADD_NVIDIA}" == "true" ]]; then
  comfy --skip-prompt install --fast-deps --nvidia
else
  comfy --skip-prompt install --fast-deps
fi

# Install custom nodes from plugins.csv (first row, comma-separated)
if [[ -f "${PLUGINS_CSV}" ]]; then
  nodes_line=$(head -n1 "${PLUGINS_CSV}" || true)
  if [[ -n "${nodes_line}" ]]; then
    # convert commas to spaces
    nodes=$(echo "$nodes_line" | tr ',' ' ')
    echo "Installing custom nodes: $nodes"
    comfy node install --fast-deps $nodes || echo "Some node installs failed"
  else
    echo "plugins.csv empty; skipping node install"
  fi
else
  echo "No plugins.csv found at ${PLUGINS_CSV}; skipping node install"
fi

# Place config files and prepare directories
echo "Creating config and custom node directories under ${COMFY_ROOT}"
mkdir -p "${COMFY_ROOT}/user/default/ComfyUI-Manager"
mkdir -p "${COMFY_ROOT}/custom_nodes/comfyui-lora-manager"
mkdir -p "${COMFY_ROOT}/temp"

if [[ -f "${CONFIG_INI}" ]]; then
  echo "Copying ${CONFIG_INI} -> ${COMFY_ROOT}/user/default/ComfyUI-Manager/config.ini"
  cp "${CONFIG_INI}" "${COMFY_ROOT}/user/default/ComfyUI-Manager/config.ini"
else
  echo "No config.ini found at ${CONFIG_INI}; skipping"
fi

# Reset models directory
echo "Resetting models directory: ${COMFY_ROOT}/models"
rm -rf "${COMFY_ROOT}/models"
mkdir -p "${COMFY_ROOT}/models"

echo "ComfyUI install logic complete."
