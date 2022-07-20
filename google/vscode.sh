#!/usr/bin/env bash

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
        "terminal.integrated.cursorWidth": 1.1,
        "terminal.integrated.fontSize": 16,
        "terminal.integrated.gpuAcceleration": "off",
        "terminal.integrated.ignoreProcessNames": [
                "bash",
                "zsh"
        ],
        "terminal.integrated.localEchoExcludePrograms": [
                "vim",
                "nano",
                "tmux"
        ],
        "terminal.integrated.fontFamily": "'Courier New', monospace",
        "terminal.integrated.lineHeight": 1.1
}
EOF