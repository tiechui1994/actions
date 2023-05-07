package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/tiechui1994/tool/speech"
	"github.com/tiechui1994/tool/util"
	"google.golang.org/api/option"
	"google.golang.org/api/youtube/v3"
)

// 大飞分享 oss.v2rayse.com
// 由零开始 agit.ai/blue/youlingkaishi
// 科技网络 github.com/guoxing123/jiedian
// 小贤哥 oss.v2rayse.com
// 玉兔分享 oss.v2rayse.com + proxy
// NodeFree nodefree.org

func FetchVideo(apiKey, channelID string) (desc, videoID string, err error) {
	service, err := youtube.NewService(context.Background(), option.WithAPIKey(apiKey))
	if err != nil {
		return desc, videoID, err
	}

	list, err := service.Search.List([]string{"snippet"}).
		ChannelId(channelID).
		MaxResults(5).
		Order("date").Do()
	if err != nil {
		return desc, videoID, err
	}

	now := time.Now().In(time.UTC).Format("2006-01-02")
	if len(list.Items) == 0 && strings.HasPrefix(list.Items[0].Snippet.PublishedAt, now) {
		videos, err := service.Videos.List([]string{"snippet"}).
			Id(list.Items[0].Id.VideoId).Do()
		if err != nil {
			return desc, videoID, err
		}

		return videos.Items[0].Snippet.Description, list.Items[0].Id.VideoId, nil
	}

	return desc, videoID, fmt.Errorf("today: %v no youtube video", now)
}

type differ struct {
	File string
	OP   string
}

func gitTodayDiffer(dir string) (files []differ, err error) {
	//git log --since='2023-05-03 00:00:00 +0000' --format='%h'
	today := time.Now().In(time.UTC).Format("2006-01-02")
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf("cd %s && git log --since='%s 00:00:00 +0000' --format='%%h'", dir, today))
	out, err := cmd.Output()
	if err != nil {
		return files, err
	}

	log.Println("git log:", strings.TrimSpace(string(out)))

	var (
		start, end string
	)
	tokens := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(tokens) <= 1 {
		start, end = "HEAD^", "HEAD"
	} else {
		start, end = tokens[len(tokens)-1], "HEAD"
	}

	cmd = exec.Command("bash", "-c",
		fmt.Sprintf("cd %s && git diff --name-status %s %s", dir, start, end))
	out, err = cmd.Output()
	if err != nil {
		return files, err
	}

	tokens = strings.Split(string(out), "\n")
	for _, token := range tokens {
		token = strings.TrimSpace(token)
		if len(token) == 0 {
			continue
		}

		kv := strings.Split(token, "\t")
		if kv[0] == "R" {
			files = append(files, differ{
				File: kv[2],
				OP:   kv[0],
			})
		} else {
			files = append(files, differ{
				File: kv[1],
				OP:   kv[0],
			})
		}
	}

	log.Println("git diff:", start, end, files)

	return files, nil
}

func FetchLatestFile(git, branch string) (result []string, err error) {
	dir, err := os.MkdirTemp("", "git")
	if err != nil {
		return result, err
	}
	defer func() {
		_ = os.RemoveAll(dir)
	}()

	// git clone --depth=20 http://github.com/xyz/xyz.git /tmp/xyz
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf("git clone --depth=20 --branch=%s %s %s", branch, git, dir))
	_, err = cmd.Output()
	if err != nil {
		return result, err
	}

	files, err := gitTodayDiffer(dir)
	if err != nil {
		return result, err
	}

	rgroup := regexp.MustCompile(`proxy-groups:`)
	rproxy := regexp.MustCompile(`proxies:`)
	for _, file := range files {
		if file.OP == "D" {
			continue
		}

		data, err := ioutil.ReadFile(filepath.Join(dir, file.File))
		if err != nil {
			continue
		}

		log.Printf("file: %v, match: %v", file.File,
			rproxy.Match(data) && rgroup.Match(data))
		if rproxy.Match(data) && rgroup.Match(data) {
			result = append(result, file.File)
		}
	}

	return result, nil
}

func PullGitFiles(git, branch string, key string) (err error) {
	endpoint := git[:len(git)-len(".git")]
	files, err := FetchLatestFile(git, branch)
	if err != nil {
		return err
	}

	var urls []string
	if strings.HasPrefix(git, "https://github.com") {
		for _, file := range files {
			urls = append(urls, strings.ReplaceAll(endpoint, "github.com", "raw.githubusercontent.com")+"/"+
				filepath.Join(branch, file))
		}
	} else if strings.HasPrefix(git, "https://agit.ai") {
		for _, file := range files {
			urls = append(urls, endpoint+"/"+
				filepath.Join("raw/branch", branch, file))
		}
	}

	log.Println("key:", key, "urls:", urls)

	if len(urls) == 0 {
		return nil
	}

	key = time.Now().In(time.UTC).Format("20060102") + "_" + key
	return UploadCache(key, urls)
}

func PullFormatFiles(format string, key string) (err error) {
	date := time.Now().In(time.UTC)
	y, m, d := date.Date()

	url := format
	url = strings.ReplaceAll(url, "${Y}", fmt.Sprintf("%04d", y))
	url = strings.ReplaceAll(url, "${M}", fmt.Sprintf("%02d", m))
	url = strings.ReplaceAll(url, "${D}", fmt.Sprintf("%02d", d))

	var urls []string
	rgroup := regexp.MustCompile(`proxy-groups:`)
	rproxy := regexp.MustCompile(`proxies:`)
	raw, err := util.GET(url, util.WithRetry(3))
	if err != nil {
		return err
	}
	if rproxy.Match(raw) && rgroup.Match(raw) {
		urls = append(urls, url)
	}

	log.Println("key:", key, "urls:", urls)
	if len(urls) == 0 {
		return nil
	}

	key = time.Now().In(time.UTC).Format("20060102") + "_" + key
	return UploadCache(key, urls)
}

func PullYoutubeFiles(apiKey, channelID string, rURL, rPwd, rLanZou *regexp.Regexp, key string) (err error) {
	desc, videoID, err := FetchVideo(apiKey, channelID)
	if err != nil {
		return err
	}

	uRLs := rURL.FindAllStringSubmatch(desc, 1)
	if len(uRLs) == 0 || len(uRLs[0]) < 1 {
		return fmt.Errorf("invalid url")
	}
	url := uRLs[0][1]

	// get youtube mp3 file
	u := fmt.Sprintf("https://web.quinn.eu.org/youtube?url=%v",
		fmt.Sprintf("https://www.youtube.com?v=%v", videoID))
	raw, err := util.GET(u, util.WithRetry(3))
	if err != nil {
		return err
	}
	var videoFile struct {
		Audio []struct {
			URL    string `json:"url"`
			Acodec string `json:"acodec"`
		} `json:"a"`
	}
	err = json.Unmarshal(raw, &videoFile)
	if err != nil {
		return err
	}

	// get password
	raw, err = util.GET(videoFile.Audio[0].URL, util.WithRetry(3))
	if err != nil {
		return err
	}

	tmp, _ := os.MkdirTemp("", "music")
	_ = ioutil.WriteFile(tmp, raw, 0666)

	password, err := speech.SpeechToText(tmp)
	if err != nil {
		return err
	}
	passwords := rPwd.FindAllStringSubmatch(password, 1)
	if len(passwords) == 0 || len(passwords[0]) < 1 {
		return fmt.Errorf("invalid password")
	}
	pwd := passwords[0][1]

	// get lanzou file
	u = fmt.Sprintf("https://web.quinn.eu.org/lanzou?url=%v&pwd=%v",
		url, pwd)
	raw, err = util.GET(u, util.WithRetry(3))
	if err != nil {
		return err
	}
	// TODO: 解析蓝奏云, 获取链接

	var urls []string
	log.Println("key:", key, "urls:", urls)

	if len(urls) == 0 {
		return nil
	}

	key = time.Now().In(time.UTC).Format("20060102") + "_" + key
	return UploadCache(key, urls)
}

func UploadCache(k string, v interface{}) error {
	try := false
again:
	raw, err := util.POST(*freeCache+"?key="+k, util.WithBody(map[string]interface{}{
		"value": v,
		"ttl":   7 * 24 * 60 * 60,
	}), util.WithRetry(2))
	if err != nil {
		if !try {
			try = !try
			goto again
		}
		return err
	}

	if strings.Contains(string(raw), "error") {
		if !try {
			try = !try
			goto again
		}
		return fmt.Errorf("upload cache failed")
	}

	return nil
}

type Config struct {
	Name string            `json:"name"`
	Type string            `json:"type"`
	Meta map[string]string `json:"meta"`
}

const (
	TypeGit     = "git"
	TypeYouTube = "youtube"
	TypeFormat  = "format"
)

var (
	freeConfig = flag.String("config", "", "config content")
	freeCache  = flag.String("cache", "", "cache url")
)

func init() {
	log.SetFlags(log.Ldate | log.Lshortfile | log.Ltime)
	log.SetPrefix("[free] ")
}

func main() {
	flag.Parse()
	if *freeCache == "" || *freeConfig == "" {
		log.Printf("config and cache must be set")
		os.Exit(1)
	}

	raw, err := base64.StdEncoding.DecodeString(*freeConfig)
	if err != nil {
		log.Printf("config is invalid")
		os.Exit(1)
	}

	var configs []Config
	err = json.Unmarshal(raw, &configs)
	if err != nil {
		log.Printf("Unmarshal failed: %v", err)
		os.Exit(2)
	}

	for _, config := range configs {
		switch config.Type {
		case TypeGit:
			log.Printf("type=%q name=%s url=%s branch=%s", config.Type, config.Name,
				config.Meta["url"], config.Meta["branch"])
			err = PullGitFiles(config.Meta["url"], config.Meta["branch"], config.Name)
			if err != nil {
				log.Printf("PullGitFiles url=%q failed; %v", config.Meta["url"], err)
			}
		case TypeFormat:
			log.Printf("type=%q name=%s url=%s", config.Type, config.Name,
				config.Meta["url"])
			err = PullFormatFiles(config.Meta["url"], config.Name)
			if err != nil {
				log.Printf("PullFormatFiles url=%q failed; %v", config.Meta["url"], err)
			}
		default:
			log.Println("not support")
		}
	}
}
