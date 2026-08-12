# Seeded by the Paseo add-on on first start, and never overwritten afterwards --
# edit it freely. It lives on /data, so it survives restarts and add-on updates.
# Delete it and restart to get this default back.

# Interactive shells only.
case $- in
    *i*) ;;
      *) return ;;
esac

# --- History ---------------------------------------------------------------
# Terminal panes come and go; history that does not survive them is useless.
HISTSIZE=50000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
HISTIGNORE='ls:ll:cd:pwd:exit:clear:history'
HISTTIMEFORMAT='%F %T  '
shopt -s histappend cmdhist
# Append after every command rather than only on exit, so a pane that is closed
# abruptly -- or several open at once -- do not lose or clobber each other.
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# --- Shell behaviour -------------------------------------------------------
shopt -s checkwinsize globstar cdspell dirspell autocd 2>/dev/null

# --- Colour ----------------------------------------------------------------
if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
fi
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias diff='diff --color=auto'
export LESS='-R -F -X'

# --- Aliases ---------------------------------------------------------------
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status --short --branch'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'

# --- Completion ------------------------------------------------------------
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
    # shellcheck source=/dev/null
    . /etc/bash_completion
fi

# Generated once and cached: shelling out to every CLI on each new pane makes
# the prompt visibly slow.
_ha_paseo_completion_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ha-paseo/completions.bash"
if [[ ! -s "$_ha_paseo_completion_cache" ]]; then
    mkdir -p "$(dirname "$_ha_paseo_completion_cache")"
    { command -v gh >/dev/null 2>&1 && gh completion -s bash; } \
        > "$_ha_paseo_completion_cache" 2>/dev/null || true
fi
if [[ -s "$_ha_paseo_completion_cache" ]]; then
    # shellcheck source=/dev/null
    . "$_ha_paseo_completion_cache"
fi

# --- Prompt ----------------------------------------------------------------
# Exit status only when non-zero, and the git branch when there is one. A
# command substitution per prompt is fine here; `git branch --show-current` is
# cheap and these are small repos.
_ha_paseo_ps1() {
    local rc=$?
    local reset='\[\e[0m\]' dim='\[\e[2m\]' cyan='\[\e[36m\]' green='\[\e[32m\]'
    local yellow='\[\e[33m\]' red='\[\e[31m\]'
    local branch=''
    if branch="$(git branch --show-current 2>/dev/null)" && [[ -n "$branch" ]]; then
        branch=" ${yellow}(${branch})${reset}"
    else
        branch=''
    fi
    local status=''
    (( rc != 0 )) && status=" ${red}[${rc}]${reset}"
    PS1="${dim}paseo${reset} ${cyan}\w${reset}${branch}${status}\n${green}\$${reset} "
}
PROMPT_COMMAND="_ha_paseo_ps1; ${PROMPT_COMMAND}"

# --- fzf, if present -------------------------------------------------------
# Ctrl-R over history is the single biggest upgrade to a bare shell.
for _f in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/fzf/key-bindings.bash; do
    if [[ -f "$_f" ]]; then
        # shellcheck source=/dev/null
        . "$_f"
        break
    fi
done
unset _f

# --- What this box can do --------------------------------------------------
# Shown once per pane. Delete this block if it gets in the way.
if [[ -z "${HA_PASEO_NO_BANNER:-}" ]]; then
    printf '\e[2m'
    printf 'ha-paseo-doctor  state of shims, services, ports, workspaces\n'
    printf 'agent-login      which agent CLIs are authenticated\n'
    printf 'ha-inventory     entities, services and areas on this HA instance\n'
    printf 'hass-api         authenticated Home Assistant REST calls\n'
    printf 'update-agents    update claude/codex/opencode/gemini/copilot\n'
    printf '\e[0m\n'
fi
