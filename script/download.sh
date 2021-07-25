#!/usr/bin/env bash

name=$1
url=$2

declare -r  SUCCESS=0
declare -r  FAILURE=1

# log
log_error(){
    red="\033[97;41m"
    reset="\033[0m"
    msg="[E] $@"
    echo -e "$red$msg$reset"
}
log_warn(){
    yellow="\033[90;43m"
    reset="\033[0m"
    msg="[W] $@"
    echo -e "$yellow$msg$reset"
}
log_info() {
    green="\033[97;42m"
    reset="\033[0m"
    msg="[I] $@"
    echo -e "$green$msg$reset"
}

common_download() {
    name=$1
    url=$2
    cmd=$3

    if [[ -d "$name" ]]; then
        log_info "$name has exist !!"
        return ${SUCCESS} #1
    fi


    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    command_exists "$cmd"
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o "$name" ${url}
    else
        curl -C - --insecure --silent -L ${url} -o "$name"
    fi

    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}.tar.gz
        return ${FAILURE}
    fi

    log_info "success to download $name"
    log_info "$(file ${name})"

    return ${SUCCESS} #3
}

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

common_download ${name} ${url} axel