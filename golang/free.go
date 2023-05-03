package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/tiechui1994/tool/util"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// 大飞分享 oss.v2rayse.com
// 由零开始 agit.ai/blue/youlingkaishi
// 科技网络 github.com/guoxing123/jiedian
// 小贤哥 oss.v2rayse.com
// 玉兔分享 oss.v2rayse.com + proxy
// NodeFree nodefree.org

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
		case "git":
			log.Printf("type=%q name=%s url=%s branch=%s", config.Type, config.Name,
				config.Meta["url"], config.Meta["branch"])
			err = PullGitFiles(config.Meta["url"], config.Meta["branch"], config.Name)
			if err != nil {
				log.Printf("PullGitFiles url=%q failed; %v", config.Meta["url"], err)
			}
		default:
			log.Println("not support")
		}
	}
}
