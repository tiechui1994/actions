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
	"sort"
	"strconv"
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

func GetNow() time.Time {
	now, err := time.ParseInLocation("2006-01-02", *freeDate, time.UTC)
	if err != nil {
		now = time.Now().In(time.UTC)
	}

	return now
}

func FetchVideo(apiKey, channelID string) (desc, videoID string, err error) {
	service, err := youtube.NewService(context.Background(), option.WithAPIKey(apiKey))
	if err != nil {
		return desc, videoID, err
	}

	list, err := service.Search.List([]string{"snippet"}).
		ChannelId(channelID).
		MaxResults(8).
		Order("date").Do()
	if err != nil {
		return desc, videoID, err
	}

	now := GetNow().Format("2006-01-02")
	if len(list.Items) > 0 {
		for _, v := range list.Items {
			if strings.HasPrefix(v.Snippet.PublishedAt, now) {
				videos, err := service.Videos.List([]string{"snippet"}).
					Id(list.Items[0].Id.VideoId).Do()
				if err != nil {
					return desc, videoID, err
				}

				return videos.Items[0].Snippet.Description, list.Items[0].Id.VideoId, nil
			}
		}
	}

	return desc, videoID, fmt.Errorf("today: %v no youtube video", now)
}

type differ struct {
	File string
	OP   string
	Date int64
}

func getFileModifyDate(dir, path string) int64 {
	// git log --follow --pretty='%at' --max-count=1 go.mod
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf("cd %s && git log --follow --pretty='%%at' --max-count=1 %s", dir, path))
	out, err := cmd.Output()
	if err != nil {
		return 0
	}

	fmt.Println(path, strings.TrimSpace(string(out)))
	v, _ := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
	return v
}

func gitTodayDiffer(dir string) (files []differ, err error) {
	//git log --since='2023-05-03 00:00:00 +0000' --format='%h'
	today := GetNow().Format("2006-01-02")
	cmd := exec.Command("bash", "-c",
		fmt.Sprintf("cd %s && git log --since='%s 00:00:00 +0000' --until='%s 23:59:59 +0000' --format='%%h'",
			dir, today, today))
	out, err := cmd.Output()
	if err != nil {
		return files, err
	}

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
				Date: getFileModifyDate(dir, kv[2]),
			})
		} else if kv[0] == "D" {
			continue
		} else {
			files = append(files, differ{
				File: kv[1],
				OP:   kv[0],
				Date: getFileModifyDate(dir, kv[1]),
			})
		}
	}

	log.Println("git diff:", start, end, files)

	return files, nil
}

func fetchLatestGitFile(git, branch string) (result []string, err error) {
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

	sort.Slice(files, func(i, j int) bool {
		return files[i].Date > files[j].Date
	})

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

	log.Println("git files:", result)
	return result, nil
}

func PullGitFiles(git, branch string, key string) (err error) {
	endpoint := git[:len(git)-len(".git")]
	files, err := fetchLatestGitFile(git, branch)
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

	key = GetNow().Format("20060102") + "_" + key
	log.Println("key:", key, "urls:", urls)
	if len(urls) == 0 {
		return nil
	}

	return UploadCache(key, urls)
}

func PullFormatFiles(format string, key string) (err error) {
	now := GetNow()
	y, m, d := now.Date()

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

	key = now.Format("20060102") + "_" + key
	log.Println("key:", key, "urls:", urls)
	if len(urls) == 0 {
		return nil
	}

	return UploadCache(key, urls)
}

func PullYoutubeFiles(apiKey, channelID string, rURL, rPwd, rLanZouName, rLanZouContent *regexp.Regexp, key string) (err error) {
	desc, videoID, err := FetchVideo(apiKey, channelID)
	if err != nil {
		return err
	}

	uRLs := rURL.FindAllStringSubmatch(desc, 1)
	if len(uRLs) == 0 || len(uRLs[0]) < 1 {
		return fmt.Errorf("invalid url")
	}
	url := uRLs[0][1]

	log.Printf("lanzou cloud url: %v", url)

	// pwd
	var pwd string
	passwords := rPwd.FindAllStringSubmatch(desc, 1)
	if len(passwords) == 0 || len(passwords[0]) < 1 {
		// download mp3 file(password contains)
		tmp, _ := os.MkdirTemp("", "music")
		mp3File := filepath.Join(tmp, "youtube.mp3")

		err = speech.FetchYouTubeAudio(videoID, mp3File)
		if err != nil {
			return fmt.Errorf("download youtube mp3 file failed: %w", err)
		}

		log.Printf("mp3 file save in: %v.", mp3File)

		// speech mp3 to text
		password, err := speech.SpeechToText(mp3File)
		if err != nil {
			return fmt.Errorf("speech to text failed: %w", err)
		}
		passwords := rPwd.FindAllStringSubmatch(password, 1)
		if len(passwords) == 0 || len(passwords[0]) < 1 {
			return fmt.Errorf("invalid password")
		}
		pwd = passwords[0][1]
	} else {
		pwd = passwords[0][1]
	}

	log.Printf("lan zou cloud file password: %v.", pwd)

	// get lanzou file
	files, err := speech.FetchLanZouInfo(url, pwd)
	if err != nil {
		return fmt.Errorf("get lanzou cloud url failed: %w", err)
	}

	for _, file := range files {
		if rLanZouName.MatchString(file.Name) {
			log.Printf("lanzou file: %v, url: %v, %v", file.Name, file.Share, file.Download)
			u, err := speech.LanZouRealURL(file.Download)
			if err != nil {
				log.Printf("get real download file url failed: %v", err)
				return fmt.Errorf("get real download file url failed: %v", err)
			}

			raw, err := util.GET(u, util.WithRetry(2))
			if err != nil {
				log.Printf("donwload file: %v failed: %v", file.Share, err)
				return fmt.Errorf("donwload file: %v faile: %v", file.Share, err)
			}

			values := rLanZouContent.FindAllStringSubmatch(string(raw), 1)
			if len(values) == 0 || len(values[0]) < 2 {
				log.Printf("match file content %v failed", rLanZouContent.String())
				return fmt.Errorf("match file content %v failed", rLanZouContent.String())
			}

			key = GetNow().Format("20060102") + "_" + key
			log.Printf("key: %v urls: %v", key, values[0][1])
			return UploadCache(key, []string{values[0][1]})
		}
	}

	return fmt.Errorf("no match lanzou file, pealse check")
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
	freeDate   = flag.String("date", "", "pull date")
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
				log.Printf("PullFormatFiles url=%q failed: %v", config.Meta["url"], err)
			}
		case TypeYouTube:
			log.Printf("type=%q name=%s", config.Type, config.Name)
			rURL := regexp.MustCompile(config.Meta["url"])
			rPWD := regexp.MustCompile(config.Meta["pwd"])
			rLanZouName := regexp.MustCompile(config.Meta["name"])
			rLanZouContent := regexp.MustCompile(config.Meta["content"])
			err = PullYoutubeFiles(config.Meta["apikey"],
				config.Meta["channelid"], rURL, rPWD, rLanZouName, rLanZouContent, config.Name)
			if err != nil {
				log.Printf("PullYoutubeFiles url=%q failed; %v", config.Meta["url"], err)
			}
		default:
			log.Println("not support")
		}
	}
}
