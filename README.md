# ai-setup

Minimal helper repository containing a small ComfyUI installer script and configuration files.

What’s included
- `install-comfyui.sh` — a standalone installer script (bash) that installs `comfy-cli`, optional cloudflared, custom nodes from `plugins.csv`, and copies `config.ini` into the expected ComfyUI user folder.
- `config.ini` — example/default configuration consumed by the installer.
- `plugins.csv` — comma-separated list of custom nodes to install.

Quick start
1. Inspect and adjust `config.ini` and `plugins.csv` as needed.
2. Run the installer on a Linux/macOS system with Python available (it uses pip):

```bash
bash install-comfyui.sh
```

Notes
- The installer was written as a minimal, best-effort helper and assumes a POSIX environment (bash). On Windows use WSL or adapt the steps for PowerShell.
- The script will attempt to install `cloudflared` only when `apt-get` is available.

License
This project is provided under the MIT License — see `LICENSE`.

Contributing
If you make improvements (Windows support, PowerShell installer, more robust dependency handling), please open a PR or create an issue.
