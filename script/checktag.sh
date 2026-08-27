#!/usr/bin/env bash

TOKEN=$1
TAG=$2

declare -r success=0
declare -r failure=1

# log
log_error(){
    red="\033[31;1m"
    reset="\033[0m"
    msg="[E] $@"
    echo -e "$red$msg$reset"
}
log_warn(){
    yellow="\033[33;1m"
    reset="\033[0m"
    msg="[W] $@"
    echo -e "$yellow$msg$reset"
}
log_info() {
    green="\033[32;1m"
    reset="\033[0m"
    msg="[I] $@"
    echo -e "$green$msg$reset"
}

check() {
    url=https://api.github.com/repos/tiechui1994/actions/releases/tags/${TAG}
    result=$(curl -H "Accept: application/vnd.github.v3+json" ${url})
    log_info "result: ${result}"
    # 使用 Bash 通配符检查响应体中是否包含 "message": "Not Found"
    if [[ "${result}" == *'"message":"Not Found"'* ]] || [[ "${result}" == *'"message": "Not Found"'* ]]; then
        echo "needbuild=${success}" >> "$GITHUB_OUTPUT"
        return
    fi

    echo "needbuild=${failure}" >> "$GITHUB_OUTPUT"
}

check