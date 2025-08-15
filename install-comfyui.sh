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
COMFY_ROOT=${COMFY_ROOT:-"$HOME/comfy"}
PLUGINS_CSV=${PLUGINS_CSV:-"./plugins.csv"}
CONFIG_INI=${CONFIG_INI:-"./config.ini"}
# Default URLs for remote config/plugins (can be overridden via env vars)
# By default these point at the raw files in the repository; override with
# CONFIG_INI_URL and PLUGINS_CSV_URL to use other locations.
CONFIG_INI_URL=${CONFIG_INI_URL:-"https://raw.githubusercontent.com/tg-tjmitchell/ai-setup/main/config.ini"}
PLUGINS_CSV_URL=${PLUGINS_CSV_URL:-"https://raw.githubusercontent.com/tg-tjmitchell/ai-setup/main/plugins.csv"}

echo "ComfyUI installer (standalone)"

# Determine whether COMFY_ROOT points directly at an existing ComfyUI repo (legacy behavior)
# or is a base directory under which we should place the repo in a subfolder (new behavior).
COMFY_UI_DIR="" # final path to actual ComfyUI repository
if [[ -d "${COMFY_ROOT}" && -f "${COMFY_ROOT}/main.py" ]]; then
  # Looks like COMFY_ROOT already IS the repo (legacy usage where COMFY_ROOT ended in ComfyUI)
  COMFY_UI_DIR="${COMFY_ROOT}"
  COMFY_BASE="$(dirname "${COMFY_ROOT}")"
else
  # Treat COMFY_ROOT as a base directory that will contain the repo folder 'ComfyUI'
  COMFY_BASE="${COMFY_ROOT}"
  COMFY_UI_DIR="${COMFY_BASE}/ComfyUI"
fi

echo "COMFY_BASE=${COMFY_BASE} COMFY_UI_DIR=${COMFY_UI_DIR} ADD_NVIDIA=${ADD_NVIDIA}"

# Helper: download a file to a destination if possible (uses curl or wget)
download_file() {
  local url="$1" dest="$2"
  if [[ -z "${url:-}" ]]; then
    return 1
  fi
  echo "Attempting to download ${dest} from ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${url}"
    return $?
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${dest}" "${url}"
    return $?
  else
    echo "No curl or wget available to download ${url}"
    return 2
  fi
}

# Ensure pip and comfy-cli
echo "Upgrading pip and installing comfy-cli"
python -m pip install --upgrade pip
python -m pip install --no-cache-dir comfy-cli
# Optional cloudflared installation: only if apt-get is available (best-effort)
if command -v apt-get >/dev/null 2>&1; then
  # Check if cloudflared is already installed to avoid unnecessary install attempts
  if command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared is already installed: $(cloudflared --version 2>/dev/null || true)"
  else
    echo "Attempting cloudflared install (apt-based)"
    tmpdeb=$(mktemp --suffix=.deb)
    if curl -fsSL -o "$tmpdeb" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb; then
      set +e
      apt-get update && apt-get install -y "$tmpdeb" || (dpkg -i "$tmpdeb" && apt-get install -f -y)
      set -e
      rm -f "$tmpdeb"
    else
      echo "Could not download cloudflared; skipping"
      rm -f "$tmpdeb" || true
    fi
  fi
else
  echo "apt-get not found; skipping cloudflared install"
fi

# Run comfy install so the repository ends up at COMFY_UI_DIR.
mkdir -p "${COMFY_BASE}"
if [[ -d "${COMFY_UI_DIR}" ]]; then
  echo "Existing install detected at ${COMFY_UI_DIR}; skipping comfy install step"
else
  echo "Running comfy install (fast-deps) in base ${COMFY_BASE} producing ${COMFY_UI_DIR}";
  (
    cd "${COMFY_BASE}";
    if [[ "${ADD_NVIDIA}" == "true" ]]; then
      comfy --skip-prompt install --fast-deps --nvidia
    else
      comfy --skip-prompt install --fast-deps
    fi
  )
fi

# Install custom nodes from plugins.csv (first row, comma-separated)
if [[ -f "${PLUGINS_CSV}" ]]; then
  echo "Found ${PLUGINS_CSV} locally"
else
  # Try to download plugins.csv if a URL is available
  if [[ -n "${PLUGINS_CSV_URL:-}" ]]; then
    if download_file "${PLUGINS_CSV_URL}" "${PLUGINS_CSV}"; then
      echo "Downloaded plugins.csv -> ${PLUGINS_CSV}"
    else
      echo "Could not download plugins.csv from ${PLUGINS_CSV_URL}; proceeding without it"
    fi
  else
    echo "No plugins.csv found at ${PLUGINS_CSV} and no PLUGINS_CSV_URL provided; skipping node install"
  fi
fi

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
fi

# Place config files and prepare directories
echo "Creating config and custom node directories under ${COMFY_UI_DIR}"
mkdir -p "${COMFY_UI_DIR}/user/default/ComfyUI-Manager"
mkdir -p "${COMFY_UI_DIR}/custom_nodes/comfyui-lora-manager"
mkdir -p "${COMFY_UI_DIR}/temp"

if [[ -f "${CONFIG_INI}" ]]; then
  echo "Copying ${CONFIG_INI} -> ${COMFY_UI_DIR}/user/default/ComfyUI-Manager/config.ini"
  cp "${CONFIG_INI}" "${COMFY_UI_DIR}/user/default/ComfyUI-Manager/config.ini"
else
  # Try to download config.ini if a URL is available
  if [[ -n "${CONFIG_INI_URL:-}" ]]; then
    if download_file "${CONFIG_INI_URL}" "${CONFIG_INI}"; then
  echo "Downloaded config.ini -> ${CONFIG_INI}; copying to ${COMFY_UI_DIR}/user/default/ComfyUI-Manager/config.ini"
  cp "${CONFIG_INI}" "${COMFY_UI_DIR}/user/default/ComfyUI-Manager/config.ini" || echo "Failed to copy downloaded config.ini"
    else
      echo "Could not download config.ini from ${CONFIG_INI_URL}; skipping"
    fi
  else
    echo "No config.ini found at ${CONFIG_INI} and no CONFIG_INI_URL provided; skipping"
  fi
fi

# Reset models directory
echo "Resetting models directory: ${COMFY_UI_DIR}/models"
rm -rf "${COMFY_UI_DIR}/models"
mkdir -p "${COMFY_UI_DIR}/models"

echo "ComfyUI install logic complete."
