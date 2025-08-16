#!/usr/bin/env bash
set -euo pipefail

# Ultra-simplified ComfyUI installer.
# Goals:
# 1. Pick (or create) a workspace directory.
# 2. Install/upgrade comfy-cli.
# 3. Run `comfy --here install` (optionally with --nvidia) inside that workspace.
# 4. If a local plugins.csv exists, install first-row nodes.
# 5. If a local config.ini exists, place it where ComfyUI Manager expects it.

ADD_NVIDIA=${ADD_NVIDIA:-true}
# Default workspace is the directory from which this script is invoked (current dir)
WORKSPACE=${WORKSPACE:-"$PWD"}
PLUGINS_CSV=${PLUGINS_CSV:-"./plugins.csv"}
CONFIG_INI=${CONFIG_INI:-"./config.ini"}
PLUGINS_CSV_URL=${PLUGINS_CSV_URL:-"https://raw.githubusercontent.com/tg-tjmitchell/ai-setup/main/plugins.csv"}
CONFIG_INI_URL=${CONFIG_INI_URL:-"https://raw.githubusercontent.com/tg-tjmitchell/ai-setup/main/config.ini"}
VENV_DIR=${VENV_DIR:-".venv"}
USE_VENV=${USE_VENV:-false}   # Set to 'false' to skip creating/using a virtual environment
export TERM=dumb
export NO_COLOR=1
export PYTHONIOENCODING=utf-8

# Directory of this script (original repo dir) in case we need to copy local files after cd
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

# Simple downloader (curl or wget). Usage: download_file URL DEST
download_file() {
  local url="$1" dest="$2"
  [[ -z "$url" ]] && return 1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dest" "$url" && return 0 || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" && return 0 || return 1
  else
    echo "(info) Neither curl nor wget available for download of $url" >&2
    return 2
  fi
}

echo "==> ComfyUI simple install"
echo "WORKSPACE=${WORKSPACE} ADD_NVIDIA=${ADD_NVIDIA}"

mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

if [[ "${USE_VENV}" == "true" ]]; then
  echo "==> Creating / activating virtual environment (${VENV_DIR})"
  if [[ ! -d "${VENV_DIR}" ]]; then
    python -m venv "${VENV_DIR}" || { echo "Failed to create venv"; exit 1; }
  fi
  if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"
  elif [[ -f "${VENV_DIR}/Scripts/activate" ]]; then
    # shellcheck disable=SC1091
    source "${VENV_DIR}/Scripts/activate"
  else
    echo "Could not locate activate script in ${VENV_DIR}" >&2
    exit 1
  fi
else
  echo "==> Skipping virtual environment (USE_VENV=${USE_VENV})"
fi
echo "==> Using python: $(command -v python)"

echo "==> Ensuring comfy-cli is available"
python -m pip install --upgrade pip >/dev/null 2>&1 || true
python -m  pip install comfy-cli

echo "==> Running comfy install (--here)"
if [[ "${ADD_NVIDIA}" == "true" ]]; then
  comfy --here --skip-prompt install --fast-deps --nvidia
else
  comfy --here --skip-prompt install --fast-deps
fi

COMFY_ROOT="${PWD}/ComfyUI"

# Ensure plugins.csv (try local repo copy, else download if missing)
if [[ ! -f "${PLUGINS_CSV}" ]]; then
  if [[ -f "${SCRIPT_DIR}/$(basename "${PLUGINS_CSV}")" ]]; then
    cp "${SCRIPT_DIR}/$(basename "${PLUGINS_CSV}")" "${PLUGINS_CSV}" && echo "==> Copied plugins.csv from script directory"
  else
    download_file "${PLUGINS_CSV_URL}" "${PLUGINS_CSV}" && echo "==> Downloaded plugins.csv" || echo "(info) plugins.csv unavailable (skipping custom nodes)"
  fi
fi

# Optional: custom nodes from plugins.csv (first line, comma separated)
if [[ -f "${PLUGINS_CSV}" ]]; then
  first_line=$(head -n1 "${PLUGINS_CSV}" || true)
  if [[ -n "${first_line}" ]]; then
    echo "==> Installing custom nodes from ${PLUGINS_CSV}"
    nodes=$(echo "${first_line}" | tr ',' ' ')
    comfy --here node install --fast-deps ${nodes} || echo "(warning) Some node installs failed"
  fi
fi

# Ensure config.ini (try local repo copy, else download if missing)
if [[ ! -f "${CONFIG_INI}" ]]; then
  if [[ -f "${SCRIPT_DIR}/$(basename "${CONFIG_INI}")" ]]; then
    cp "${SCRIPT_DIR}/$(basename "${CONFIG_INI}")" "${CONFIG_INI}" && echo "==> Copied config.ini from script directory"
  else
    download_file "${CONFIG_INI_URL}" "${CONFIG_INI}" && echo "==> Downloaded config.ini" || echo "(info) config.ini unavailable (continuing)"
  fi
fi

# Optional: copy config.ini into expected path
if [[ -f "${CONFIG_INI}" ]]; then
  target_dir="${COMFY_ROOT}/user/default/ComfyUI-Manager"
  mkdir -p "${target_dir}"
  cp "${CONFIG_INI}" "${target_dir}/config.ini"
  echo "==> Placed config.ini"
fi

echo "==> Done. To launch:"
echo "    cd \"${WORKSPACE}\" && comfy launch"
echo "(You can add arguments after 'comfy launch' if needed.)"
