#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manager="$script_dir/manage-devops-terminal.sh"

bash "$manager" verify

printf '\nVersions terminal V10\n'
starship --version | head -n 1
fzf --version | head -n 1
zoxide --version | head -n 1
eza --version | head -n 1
rg --version | head -n 1
if command -v fd >/dev/null 2>&1; then fd --version | head -n 1; else fdfind --version | head -n 1; fi
if command -v bat >/dev/null 2>&1; then bat --version | head -n 1; else batcat --version | head -n 1; fi
tree --version | head -n 1

printf '\nVERDICT: V10 DEVOPS TERMINAL READY\n'
