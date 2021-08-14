#!/usr/bin/env bash

DATE=$1

declare -r datetime=${DATE:="$(date +'%Y-%m-%d')"}
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


common_download() {
    name=$1
    url=$2
    cmd=$3

    filename=${name%%.*}

    if [[ -d "$filename" ]]; then
        log_info "$name has exist"
        return ${success} #1
    fi

    if [[ -f "$name" && -n $(file "$name" | grep -o 'compressed data') ]]; then
        rm -rf ${filename} && mkdir ${filename}
        tar -xvf ${name} -C ${filename} --strip-components 1
        if [[ $? -ne 0 ]]; then
            log_error "$name decopress failed"
            rm -rf ${filename} && rm -rf ${name}
            return ${failure}
        fi

        return ${success} #2
    fi

    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    rm -rf ${name}

    command -v "$cmd" > /dev/null 2>&1
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o ${name} ${url}
    else
        curl -C - --insecure --silent -o ${name} ${url}
    fi

    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}
        return ${failure}
    fi

    log_info "success to download $name"
    rm -rf ${filename} && mkdir ${filename}
    tar -xvf ${name} -C ${filename} --strip-components 1
    if [[ $? -ne 0 ]]; then
        log_error "$name decopress failed"
        rm -rf ${filename} && rm -rf ${name}
        return ${failure}
    fi
}

download_ffmpeg() {
    # ffmpge 4.4
    url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
    common_download "ffmpeg.tar.xz" ${url} curl

    return $?
}

download_vedio() {
    start="$(date +%s --date="$datetime 09:22:00+08:00")000"
    end="$(date +%s --date="$datetime 09:40:00+08:00")000"
    url="https://cctvalih5ca.v.myalicdn.com/live/cctv2_2/index.m3u8?begintimeabs=$start&endtimeabs=$end"
    filename="$(date +"%Y-%m-%d-09").mp4"
    ffmpeg/ffmpeg -i ${url} -c:v libx264 \
         -vcodec libx264 \
         -profile:v high \
         -pre slow \
         -bufsize 1000k \
         -b:v 720k \
         -s 960×720 \
         -threads 0 ${filename}

    if [[ $? -ne ${success} ]]; then
        return $?
    fi

    sudo mv ${filename} ${GITHUB_WORKSPACE}/${filename}
    echo "VEDIO=$filename" >> ${GITHUB_ENV}
}

execute() {
    download_ffmpeg
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi

    download_vedio
    if [[ $? -ne ${success} ]]; then
        exit $?
    fi
}

execute