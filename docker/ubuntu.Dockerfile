FROM ubuntu:18.04
RUN apt-get update && \
    apt-get install -y build-essential g++ gcc curl make tar gzip openssl git && \
    curl --insecure -L https://go.dev/dl/go1.23.4.linux-amd64.tar.gz -o /tmp/go.tgz && \
    tar xf /tmp/go.tgz -C /usr/local && rm -rf /tmp/go.tgz && \
    ln -sf /usr/local/go/bin/go /usr/bin/go && \
    go env -w GOPATH=/go GOPROXY=direct GOFLAGS="-insecure"
