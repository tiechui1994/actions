package main

import (
	"regexp"
	"testing"
)

func TestPullYoutubeKeji(t *testing.T) {
	rURL := regexp.MustCompile(`分享链接:(https://[A-z0-9_-]*?[@]?[A-z0-9]+([\-\.][a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?)`)
	rPWD := regexp.MustCompile(`密码是([0-9]{3,})`)
	rLANZOUFile := regexp.MustCompile(`客户端一键订阅.txt`)
	rLANZOUContent := regexp.MustCompile(`(https://oss\.v2rayse\.com/proxies/data/.*?\.yaml)`)
	err := PullYoutubeFiles("1111111111111",
		"222222222", rURL, rPWD, rLANZOUFile, rLANZOUContent, "xiaoxiange")
	t.Logf("%v", err)
}

func TestPullYoutubeDafei(t *testing.T) {
	rURL := regexp.MustCompile(`下载地址\s*:|：\s*(https://[A-z0-9_-]*?[@]?[A-z0-9]+([\-\.][a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?)`)
	rPWD := regexp.MustCompile(`网盘密码\s*:\s*([0-9]{3,})`)
	rLANZOUFile := regexp.MustCompile(`客户端一键订阅.txt`)
	rLANZOUContent := regexp.MustCompile(`(https://oss\.v2rayse\.com/proxies/data/.*?\.yaml)`)
	err := PullYoutubeFiles("11-111-11-11",
		"111", rURL, rPWD, rLANZOUFile, rLANZOUContent, "dafei")
	t.Logf("%v", err)
}
