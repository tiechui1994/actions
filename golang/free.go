package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"goland/notify"
	"goland/utils"
	"gopkg.in/yaml.v3"
	"io/fs"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tiechui1994/proxy/adapter"
	"github.com/tiechui1994/proxy/constant"
	"github.com/tiechui1994/tool/speech"
	"github.com/tiechui1994/tool/util"
)

type RawConfig struct {
	ProxyProvider yaml.Node                `yaml:"proxy-providers,omitempty"`
	Proxy         []map[string]interface{} `yaml:"proxies"`
	ProxyGroup    yaml.Node                `yaml:"proxy-groups"`
	Rule          yaml.Node                `yaml:"rules"`
}

func urlToMetadata(rawURL string) (addr constant.Metadata, err error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return
	}
	port := u.Port()
	if port == "" {
		switch u.Scheme {
		case "https":
			port = "443"
		case "http":
			port = "80"
		default:
			err = fmt.Errorf("%s scheme not Support", rawURL)
			return
		}
	}

	p, _ := strconv.ParseUint(port, 10, 16)
	addr = constant.Metadata{
		Host:    u.Hostname(),
		DstIP:   nil,
		DstPort: constant.Port(p),
	}
	return
}

func YamlConfigTest(file string) (u string, err error) {
	raw, err := ioutil.ReadFile(file)
	if err != nil {
		return u, fmt.Errorf("ReadFile: %w", err)
	}

	// HK Speed Test
	data, err := util.POST("https://api.quinn.eu.org/api/speed",
		util.WithBody(map[string]interface{}{"data": raw}),
		util.WithRetry(2))
	if err == nil {
		log.Printf("HK Test: %v", string(data))
		var result struct{
			URL string `json:"url"`
		}
		err = json.Unmarshal(data, &result)
		if err == nil && result.URL != "" {
			return result.URL, nil
		}
	}

	// Local Speed Test
	config := &RawConfig{}
	err = yaml.Unmarshal(raw, config)
	if err != nil {
		return u, fmt.Errorf("yaml Unmarshal: %w", err)
	}

	testWorker := func(proxy constant.ProxyAdapter, reqURL string, ms uint64, readBody bool) error {
		addr, err := urlToMetadata(reqURL)
		if err != nil {
			log.Printf("urlToMetadata:%v", err)
			return fmt.Errorf("url: %w", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(ms))
		defer cancel()

		start := time.Now()
		instance, err := proxy.DialContext(ctx, &addr)
		if err != nil {
			return err
		}
		defer instance.Close()

		req, err := http.NewRequest(http.MethodGet, reqURL, nil)
		if err != nil {
			return fmt.Errorf("request: %w", err)
		}
		req = req.WithContext(ctx)
		transport := &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return instance, nil
			},
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   15 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		}
		client := http.Client{
			Transport: transport,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}
		defer client.CloseIdleConnections()

		resp, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("client: %w", err)
		}
		defer resp.Body.Close()
		if readBody {
			raw, _ := ioutil.ReadAll(resp.Body)
			log.Printf("%v total: %v, data: %v", proxy.Name(), time.Since(start), string(raw))
		}
		return nil
	}

	var wg sync.WaitGroup
	var lock sync.Mutex
	var count int
	var balanceCount int
	var invalidIndex = make(map[int]bool)
	proxiesConfig := config.Proxy
	for idx, mapping := range proxiesConfig {
		proxy, err := adapter.ParseProxy(mapping)
		if err != nil {
			log.Printf("proxy %d: %v", idx, err)

			// will remove
			if !strings.Contains(err.Error(), "missing type") &&
				!strings.Contains(err.Error(), "unsupport proxy type") {
				invalidIndex[idx] = true
			}

			continue
		}

		count += 1
		index := idx
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			urL := "https://api6.ipify.org?format=json"
			if err := testWorker(proxy, urL, 15000, true); err == nil {
				lock.Lock()
				proxiesConfig[index]["v6"] = true
				lock.Unlock()
			}

			urL = "https://www.google.com/favicon.ico"
			if err := testWorker(proxy, urL, 4000, false); err == nil {
				lock.Lock()
				balanceCount += 1
				proxiesConfig[index]["balance"] = true
				lock.Unlock()
			}

			urL = "https://www.youtube.com/favicon.ico"
			if err := testWorker(proxy, urL, 5000, false); err == nil {
				lock.Lock()
				balanceCount += 1
				proxiesConfig[index]["video"] = true
				lock.Unlock()
			}
		}(index)
		if count == 30 {
			wg.Wait()
			count = 0
		}
	}
	if count != 0 {
		wg.Wait()
	}

	// 非法的类型
	if len(invalidIndex) > 0 {
		proxies := make([]map[string]interface{}, 0)
		for idx, val := range config.Proxy {
			if invalidIndex[idx] {
				continue
			}
			proxies = append(proxies, val)
		}
		config.Proxy = proxies
	}

	// balance数量不足, all is balance
	if balanceCount == 0 || float64(balanceCount) < 0.2*float64(len(config.Proxy)) {
		for idx := range config.Proxy {
			config.Proxy[idx]["balance"] = true
		}
	}

	temp, _ := os.MkdirTemp("", "config.yaml")
	defer os.RemoveAll(temp)

	fileName := filepath.Join(temp, "config.yaml")
	fd, err := os.Create(fileName)
	if err != nil {
		return u, fmt.Errorf("")
	}
	defer fd.Close()

	en := yaml.NewEncoder(fd)
	err = en.Encode(config)
	if err != nil {
		return u, fmt.Errorf("yaml Encoder: %w", err)
	}
	_ = fd.Sync()

	return utils.UploadFile(fileName)
}

// 大飞分享 oss.v2rayse.com
// 由零开始 agit.ai
// 科技网络 github.com
// NodeFree nodefree.org

func GetNow() time.Time {
	now, err := time.ParseInLocation("2006-01-02", *freeDate, time.UTC)
	if err != nil {
		now = time.Now().In(time.UTC)
	}

	return now
}

type differ struct {
	File     string
	OP       string
	Date     int64
	callback func() (string, error)
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

func gitTodayDiffer(dir, today string) (files []differ, err error) {
	//git log --since='2023-05-03 00:00:00 +0000' --format='%h'
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

func fetchLatestGitFile(git, branch string, convert bool) (result []string, err error) {
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

	differFiles, err := gitTodayDiffer(dir, GetNow().Format("2006-01-02"))
	if err != nil {
		return result, err
	}

	var files []differ
	for i := 0; i < len(differFiles); i++ {
		file := differFiles[i]
		if file.OP == "D" {
			continue
		}

		// 处理 zip 文件(加密)
		if strings.HasSuffix(filepath.Join(dir, file.File), ".zip") {
			distDir := filepath.Join(dir, fmt.Sprintf("temp_%v", time.Now().Unix()))
			err = utils.BruteForce(filepath.Join(dir, file.File), distDir, strings.Split("0123456789", ""))
			if err == nil {
				_ = filepath.Walk(distDir, func(path string, info fs.FileInfo, err error) error {
					if info.IsDir() {
						return err
					}
					log.Printf("zip file: %v", path)
					files = append(files, differ{
						OP:   file.OP,
						File: path[len(dir):],
						Date: file.Date,
					})
					return nil
				})
			}
			continue
		}

		// only handle types
		files = append(files, file)
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i].Date > files[j].Date
	})

	var fileList []string
	for _, file := range files {
		fileList = append(fileList, filepath.Join(dir, file.File))
	}
	list, err := utils.CombineToOneYaml(fileList, convert)
	if err != nil || len(list) == 0 {
		return result, fmt.Errorf("proxy is Empty or CombineToOneYaml: %v", err)
	}

	fileName := filepath.Join(dir, "connect.yaml")
	fd, _ := os.Create(fileName)
	defer fd.Close()
	config := &RawConfig{Proxy: list}
	err = yaml.NewEncoder(fd).Encode(config)
	if err != nil {
		return result, fmt.Errorf("yaml Unmarshal: %w", err)
	}

	u, err := YamlConfigTest(fileName)
	if err != nil {
		return result, err
	}

	return []string{u}, nil
}

func PullGitFiles(git, branch string, key string, convert bool) (err error) {
	endpoint := git[:len(git)-len(".git")]
	files, err := fetchLatestGitFile(git, branch, convert)
	if err != nil {
		return err
	}

	var urls []string
	for _, file := range files {
		if strings.HasPrefix(file, "https") {
			urls = append(urls, file)
			continue
		}

		// file path
		if strings.HasPrefix(git, "https://github.com") {
			urls = append(urls, strings.ReplaceAll(endpoint, "github.com", "raw.githubusercontent.com")+
				"/"+filepath.Join(branch, file))
		} else if strings.HasPrefix(git, "https://agit.ai") {
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

	u := format
	u = strings.ReplaceAll(u, "${Y}", fmt.Sprintf("%04d", y))
	u = strings.ReplaceAll(u, "${M}", fmt.Sprintf("%02d", m))
	u = strings.ReplaceAll(u, "${D}", fmt.Sprintf("%02d", d))

	var urls []string
	rgroup := regexp.MustCompile(`proxy-groups:`)
	rproxy := regexp.MustCompile(`proxies:`)
	raw, err := util.GET(u, util.WithRetry(3))
	if err != nil {
		return err
	}
	if rproxy.Match(raw) && rgroup.Match(raw) {
		fileName := "./nodefree.yaml"
		_ = ioutil.WriteFile(fileName, raw, 0666)
		if u, err := YamlConfigTest(fileName); err == nil {
			urls = append(urls, u)
		}
	}

	key = now.Format("20060102") + "_" + key
	log.Println("key:", key, "urls:", urls)
	if len(urls) == 0 {
		return nil
	}

	return UploadCache(key, urls)
}

func PullYoutubeFiles(apiKey, channelID string, rURL, rPwd, rLanZouName, rLanZouContent *regexp.Regexp, key string) (err error) {
	desc, videoID, err := utils.FetchVideo(apiKey, channelID, GetNow().Format("2006-01-02"))
	if err != nil {
		return err
	}

	uRLs := rURL.FindAllStringSubmatch(desc, 1)
	if len(uRLs) == 0 || len(uRLs[0]) < 1 {
		return fmt.Errorf("invalid url")
	}
	urlLanZou := uRLs[0][1]

	log.Printf("lanzou cloud url: %v", urlLanZou)

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
		password = strings.ReplaceAll(password, "\n", "")
		passwords := rPwd.FindAllStringSubmatch(password, 1)
		if len(passwords) == 0 || len(passwords[0]) < 1 {
			log.Printf("password text: %v", password)
			return fmt.Errorf("invalid password")
		}
		pwd = passwords[0][1]
	} else {
		pwd = passwords[0][1]
	}

	log.Printf("lan zou cloud file password: %v.", pwd)

	// get lanzou file
	u, _ := url.Parse(urlLanZou)
	u.Host = "www.lanzouy.com"
	files, err := speech.FetchLanZouInfo(u.String(), pwd)
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
	raw, err := util.POST(*freeCache+fmt.Sprintf("?key=%v&ttl=%v", k, 7*24*60*60), util.WithBody(v), util.WithRetry(2))
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

	to notify.EmailInfo
)

func init() {
	log.SetFlags(log.Ldate | log.Lshortfile | log.Ltime)
	log.SetPrefix("[free] ")

	to = notify.EmailInfo{
		Email: "2904951429@qq.com",
	}
	notify.DefaultURL("https://broadlink.eu.org/api/email")
	notify.DefaultFrom(notify.EmailInfo{
		Email: "no-reply@broadlink.eu.org",
	})
}

func emailJSON(v interface{}) string {
	var buf bytes.Buffer
	e := json.NewEncoder(&buf)
	e.SetIndent("", "   ")
	_ = e.Encode(v)
	return buf.String()
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

	log.Printf("%v", string(raw))

	for _, config := range configs {
		switch config.Type {
		case TypeGit:
			log.Printf("==== type=%q name=%s =========", config.Type, config.Name)
			log.Printf("git url: %s branch: %s", config.Meta["url"], config.Meta["branch"])
			convert, _ := strconv.ParseBool(config.Meta["adapter"])
			err = PullGitFiles(config.Meta["url"], config.Meta["branch"], config.Name, convert)
			if err != nil {
				log.Printf("PullGitFiles name=%q url=%q failed: %v",
					config.Name, config.Meta["url"], err)
				_ = notify.SendEmail(
					notify.WithSubject(fmt.Sprintf("Fetch Type=%s Failed At %s", config.Type, time.Now().Format(time.RFC3339))),
					notify.WithTo(to),
					notify.WithContent(notify.TypePlain, emailJSON(map[string]interface{}{
						"type":  config.Type,
						"name":  config.Name,
						"url":   config.Meta["url"],
						"error": err.Error(),
					})),
				)
			}
		case TypeFormat:
			log.Printf("======== type=%q name=%s =========", config.Type, config.Name)
			log.Printf("format url: %s", config.Meta["url"])
			err = PullFormatFiles(config.Meta["url"], config.Name)
			if err != nil {
				log.Printf("PullFormatFiles name=%q url=%q failed: %v",
					config.Name, config.Meta["url"], err)
				_ = notify.SendEmail(
					notify.WithSubject(fmt.Sprintf("Fetch Type=%s Failed At %s", config.Type, time.Now().Format(time.RFC3339))),
					notify.WithTo(to),
					notify.WithContent(notify.TypePlain, emailJSON(map[string]interface{}{
						"type":  config.Type,
						"name":  config.Name,
						"url":   config.Meta["url"],
						"error": err.Error(),
					})),
				)
			}
		case TypeYouTube:
			log.Printf("======== type=%q name=%s ========", config.Type, config.Name)
			rURL := regexp.MustCompile(config.Meta["url"])
			rPWD := regexp.MustCompile(config.Meta["pwd"])
			rLanZouName := regexp.MustCompile(config.Meta["name"])
			rLanZouContent := regexp.MustCompile(config.Meta["content"])
			log.Printf("file url regex: %s, pwd regex: %s, name regex: %s, content regex: %s",
				rURL, rPWD, rLanZouName, rLanZouContent)
			err = PullYoutubeFiles(config.Meta["apikey"],
				config.Meta["channelid"], rURL, rPWD, rLanZouName, rLanZouContent, config.Name)
			if err != nil {
				log.Printf("PullYoutubeFiles name=%q failed: %v",
					config.Name, err)
				_ = notify.SendEmail(
					notify.WithSubject(fmt.Sprintf("Fetch Type=%s Failed At %s", config.Type, time.Now().Format(time.RFC3339))),
					notify.WithTo(to),
					notify.WithContent(notify.TypePlain, emailJSON(map[string]interface{}{
						"type":  config.Type,
						"name":  config.Name,
						"url":   config.Meta["url"],
						"error": err.Error(),
					})),
				)
			}
		default:
			log.Println("not support")
		}
	}
}
