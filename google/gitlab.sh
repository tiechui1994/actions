#!/usr/bin/env bash

ubuntu='18.04'
gitlab="gitlab-ce_13.11.4-ce.0_amd64.deb"

declare -r codename=(
    ['16.04']='xenial'
    ['18.04']='bionic'
    ['20.04']='focal'
)

wget --content-disposition \
    https://packages.gitlab.com/gitlab/gitlab-ce/packages/ubuntu/${codename[ubuntu]}/${gitlab}/download.deb

cat > /etc/gitlab/gitlab.rb <<-'EOF'
external_url 'http://gitlab.example.com'

# 初始化 root 账号密码和  shared_runners 注册密码
gitlab_rails['initial_root_password'] = "1234567890"
gitlab_rails['initial_shared_runners_registration_token'] = "1234567890"
EOF

gitlab-ctl reconfigure

gitlab-ctl start
