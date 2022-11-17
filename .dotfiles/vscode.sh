#!/usr/bin/env bash

file=/workspace/.vscode-remote/data/Machine/settings.json
cat > ${file} <<-'EOF'
{
    "gitpod.openInStable.neverPrompt": true,
    "redhat.telemetry.enabled": true,

    "workbench.colorTheme": "Visual Studio Dark",
    "workbench.startupEditor": "none",

    "go.toolsManagement.checkForUpdates": "local",
    "go.useLanguageServer": true,

    "editor.fontFamily": "'Courier New', monospace",
    "editor.fontSize": 16,
    "editor.fontWeight": "normal",
    "editor.cursorStyle": "underline",

    "terminal.integrated.fontFamily": "'Courier New'",
    "terminal.integrated.cursorStyle": "underline",
    "terminal.integrated.fontSize": 17,
    "terminal.integrated.cursorWidth": 1.2,
    "terminal.integrated.lineHeight": 1.2,
    "terminal.integrated.fontWeight": "550",
    "terminal.integrated.gpuAcceleration": "on",
    "terminal.integrated.ignoreProcessNames": [
            "bash",
            "zsh"
    ],
    "terminal.integrated.localEchoExcludePrograms": [
            "vim",
            "nano",
            "tmux"
    ],
    "terminal.integrated.copyOnSelection": true,
    "terminal.integrated.cursorBlinking": true,
    "terminal.integrated.scrollback": 10000
}
EOF

# change bashrc
cat >> ${HOME}/.bashrc <<-'EOF'
__bash_prompt() {
    local gitbranch='`\
        if [ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ]; then \
            export BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null); \
            if [ "${BRANCH}" != "" ]; then \
                echo -n "\[\033[0;36m\](\[\033[1;31m\]${BRANCH}" \
                && echo -n "\[\033[0;36m\]) "; \
            fi; \
        fi`'
    local lightblue='\[\033[1;34m\]'
    local removecolor='\[\033[0m\]'
    PS1="${lightblue}\w ${gitbranch}${removecolor}\$ "
    unset -f __bash_prompt
}
__bash_prompt
EOF

source ~/.bashrc
