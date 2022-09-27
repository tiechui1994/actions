#!/usr/bin/env bash

# change
cat > $HOME/.vscode-remote/data/Machine/settings.json <<-'EOF'
{
        "go.toolsManagement.checkForUpdates": "local",
        "go.useLanguageServer": true,
        "go.gopath": "/go",
        "python.pythonPath": "/opt/python/latest/bin/python",
        "python.linting.enabled": true,
        "python.linting.pylintEnabled": "true",
        "python.formatting.autopep8Path": "/usr/local/py-utils/bin/autopep8",
        "python.formatting.blackPath": "/usr/local/py-utils/bin/black",
        "python.formatting.yapfPath": "/usr/local/py-utils/bin/yapf",
        "python.linting.banditPath": "/usr/local/py-utils/bin/bandit",
        "python.linting.flake8Path": "python.linting.flake8Path",
        "python.linting.mypyPath": "/usr/local/py-utils/bin/mypy",
        "python.linting.pycodestylePath": "/usr/local/py-utils/bin/pycodestyle",
        "python.linting.pydocstylePath": "/usr/local/py-utils/bin/pydocstyle",
        "python.linting.pylintPath": "/usr/local/py-utils/bin/pylint",
        "lldb.executable": "/usr/bin/lldb",

        "editor.fontFamily": "'Courier New', monospace",
        "editor.fontSize": 16,
        "editor.fontWeight": "normal",
        "editor.cursorStyle": "underline",
        "terminal.integrated.cursorStyle": "underline",
        "terminal.integrated.cursorWidth": 1.2,
        "terminal.integrated.fontSize": 17,
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
        "terminal.integrated.fontFamily": "'Courier New'",
        "terminal.integrated.lineHeight": 1.2,
        "terminal.integrated.copyOnSelection": true,
        "terminal.integrated.cursorBlinking": true,
        "terminal.integrated.fontWeight": "550",
        "terminal.integrated.scrollback": 10000
}
EOF

# change bashrc
read -r -d '' txt <<-'EOF'
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

lines=($(grep -E '^__bash_prompt' ~/.bashrc -o -n | cut -d ':' -f1))
begin=$((${lines[0]}-1))
end=$((${lines[1]}+1))

cat > /tmp/bashrc <<-EOF
$(sed -n "1, $begin p" ~/.bashrc)
${txt}
$(sed -n "$end, $ p" ~/.bashrc)
EOF

mv /tmp/bashrc ~/.bashrc && source ~/.bashrc
