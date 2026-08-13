# shellcheck shell=bash
# Windows_11_Pro_Custom - Bash DevOps V10
# Fichier géré par le dépôt. Les personnalisations locales vont dans:
# ~/.config/windows11-pro-custom/local.sh

case $- in
  *i*) ;;
  *) return 0 ;;
esac

export EDITOR="code --wait"
export VISUAL="$EDITOR"
export PAGER="less"
export LESS="-FRX"
export CLICOLOR=1
export COLORTERM="truecolor"
export GREP_COLORS='ms=01;31:mc=01;31:sl=:cx=:fn=35:ln=32:bn=32:se=36'

export HISTCONTROL="ignoreboth:erasedups"
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTTIMEFORMAT='%F %T  '
shopt -s histappend cmdhist lithist checkwinsize globstar 2>/dev/null || true
if [[ ";${PROMPT_COMMAND:-};" != *";history -a; history -n;"* ]]; then
  PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
fi

if [[ -r /usr/share/bash-completion/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /usr/share/bash-completion/bash_completion
elif [[ -r /etc/bash_completion ]]; then
  # shellcheck disable=SC1091
  source /etc/bash_completion
fi

if command -v eza >/dev/null 2>&1; then
  alias ll='eza -al --group-directories-first --icons=auto --git'
  alias la='eza -a --group-directories-first --icons=auto'
  alias l='eza --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --group-directories-first --icons=auto'
else
  alias ll='ls -alF --color=auto'
  alias la='ls -A --color=auto'
  alias l='ls -CF --color=auto'
  alias lt='tree -L 2 -C'
fi

if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  bat() { command batcat "$@"; }
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  fd() { command fdfind "$@"; }
fi
alias batp='bat --paging=always'
alias rgf='rg --hidden --glob "!.git"'

alias gst='git status --short --branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gpl='git pull --ff-only'
alias gps='git push'
alias glog='git log --graph --decorate --oneline --all -20'
alias gd='git diff'
alias gds='git diff --staged'

alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias di='docker images'
alias dlog='docker logs -f --tail=200'
alias dex='docker exec -it'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f --tail=200'

alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias klogs='kubectl logs -f --tail=200'
alias kexec='kubectl exec -it'

kctx() {
  if (($# == 0)); then
    kubectl config current-context
  else
    kubectl config use-context "$1"
  fi
}

kns() {
  if (($# == 0)); then
    local ns
    ns="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
    printf '%s\n' "${ns:-default}"
  else
    kubectl config set-context --current --namespace="$1"
  fi
}

alias h='helm'
alias hls='helm list -A'
alias hst='helm status'
alias hup='helm upgrade --install'

alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfo='terraform output'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'

alias a='ansible'
alias ap='ansible-playbook'
alias av='ansible-vault'
alias awswho='aws sts get-caller-identity'
alias ghpr='gh pr status'

awsp() {
  if (($# == 0)); then
    printf '%s\n' "${AWS_PROFILE:-<default>}"
  else
    export AWS_PROFILE="$1"
    printf 'AWS_PROFILE=%s\n' "$AWS_PROFILE"
  fi
}

mkcd() {
  (($# == 1)) || { printf 'Usage: mkcd <dossier>\n' >&2; return 2; }
  mkdir -p -- "$1" && cd -- "$1" || return
}

pathlines() {
  tr ':' '\n' <<<"$PATH"
}

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

if command -v gh >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  source <(gh completion -s bash)
fi

if command -v fzf >/dev/null 2>&1; then
  if fzf --bash >/dev/null 2>&1; then
    eval "$(fzf --bash)"
  else
    # shellcheck disable=SC1091
    [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]] && source /usr/share/doc/fzf/examples/key-bindings.bash
    # shellcheck disable=SC1091
    [[ -r /usr/share/doc/fzf/examples/completion.bash ]] && source /usr/share/doc/fzf/examples/completion.bash
  fi
  export FZF_DEFAULT_OPTS='--height=45% --layout=reverse --border --info=inline --cycle'
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"
fi

export STARSHIP_CONFIG="$HOME/.config/windows11-pro-custom/starship.toml"
if command -v starship >/dev/null 2>&1 && [[ -r "$STARSHIP_CONFIG" ]]; then
  eval "$(starship init bash)"
fi

WPC_LOCAL_PROFILE="$HOME/.config/windows11-pro-custom/local.sh"
if [[ -r "$WPC_LOCAL_PROFILE" ]]; then
  # shellcheck disable=SC1090
  source "$WPC_LOCAL_PROFILE"
fi
