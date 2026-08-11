# shellcheck shell=bash
# Windows_11_Pro_Custom - profil shell DevOps

export EDITOR="code --wait"
export VISUAL="$EDITOR"
export PAGER="less"
export LESS="-FRX"

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias tf='terraform'
alias k='kubectl'
alias h='helm'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias gst='git status --short --branch'

if command -v kubectl >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

if command -v helm >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  source <(helm completion bash)
fi

if command -v terraform >/dev/null 2>&1; then
  complete -C "$(command -v terraform)" terraform 2>/dev/null || true
fi
