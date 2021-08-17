#!/usr/bin/env bash

URL=$1

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

sha1() {
    name=$1

    log_info "file: $(file ${name})"
    log_info "sha1: $(cat ${name}|sha1sum)"
    log_info "size: $(ls -lh ${name}|cut -d ' ' -f5), $(ls -l ${name}|cut -d ' ' -f5)"

    echo "name: $name" >> "$name.SHA1"
    echo "size: $(ls -l ${name}|cut -d ' ' -f5)" >> "$name.SHA1"
    echo "sha1: $(cat ${name}|sha1sum)" >> "$name.SHA1"
}

download() {
    name=$1
    url=$2
    cmd=$3
    decompress=$4

    declare -A extends=(
        ["tar"]="application/x-tar"
        ["tgz"]="application/gzip"
        ["tar.gz"]="application/gzip"
        ["tar.bz2"]="application/x-bzip2"
        ["tar.xz"]="application/x-xz"
    )

    extend="${name##*.}"
    filename="${name%%.*}"
    temp=${name%.*}
    if [[ ${temp##*.} = "tar" ]]; then
         extend="${temp##*.}.${extend}"
         filename="${temp%%.*}"
    fi

    # uncompress file
    if [[ -f "$name" ]]; then
        if [[ ${decompress} && ${extends[$extend]} && $(file -i "$name") =~ ${extends[$extend]} ]]; then
            rm -rf ${filename} && mkdir ${filename}
            tar -xf ${name} -C ${filename} --strip-components 1
            if [[ $? -ne 0 ]]; then
                log_error "$name decopress failed"
                rm -rf ${filename} && rm -rf ${name}
                return ${failure}
            fi
        fi

        return ${success} #2
    fi

    # download
    log_info "$name url: $url"
    log_info "begin to donwload $name ...."
    rm -rf ${name}

    command -v "$cmd" > /dev/null 2>&1
    if [[ $? -eq 0 && "$cmd" == "axel" ]]; then
        axel -n 10 --insecure --quite -o ${name} ${url}
    else
        curl -C - --insecure  --silent --location -o ${name} ${url}
    fi
    if [[ $? -ne 0 ]]; then
        log_error "download file $name failed !!"
        rm -rf ${name}
        return ${failure}
    fi

    log_info "success to download $name"

    # uncompress file
    if [[ ${decompress} && ${extends[$extend]} && $(file -i "$name") =~ ${extends[$extend]} ]]; then
        rm -rf ${filename} && mkdir ${filename}
        tar -xf ${name} -C ${filename} --strip-components 1
        if [[ $? -ne 0 ]]; then
            log_error "$name decopress failed"
            rm -rf ${filename} && rm -rf ${name}
            return ${failure}
        fi

        return ${success} #2
    fi
}

download_ffmpeg() {
    # ffmpge 4.4
    url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
    url="https://github.com/tiechui1994/jobs/releases/download/ffmpeg_4.4/ffmpeg-release-amd64-static.tar.xz"
    download "ffmpeg.tar.xz" ${url} curl 1

    return $?
}

download_vedio() {
    # do not
    log_info "url: $url"
    ffmpeg/ffmpeg -i ${url} \
         -c:v libx264 \
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