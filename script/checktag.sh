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
    sudo apt-get update && \
    sudo apt-get install jq -y
    url=https://api.github.com/repos/tiechui1994/jobs/releases/tags/${TAG}
    result=$(curl -H "Accept: application/vnd.github.v3+json" \
                  -H "Authorization: token ${TOKEN}" ${url})
    log_info "result: $(echo ${result} | jq .)"
    message=$(echo ${result} | jq .message)
    log_info "message: ${message}"
    if [[ ${message} = '"Not Found"' ]]; then
        echo "::needbuild::${success}"
        return
    fi

    echo "::needbuild::${failure}"
}

check