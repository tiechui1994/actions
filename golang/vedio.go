package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"

	"github.com/tiechui1994/tool/log"
	"github.com/tiechui1994/tool/util"
)

func init() {
	util.LogRequest(func(request *http.Request) {
		log.Infoln("%v - %v", request.Method, request.RequestURI)
	})
}

func main() {
	name := flag.String("name", "", "dir path")
	url := flag.String("url", "", "date day")
	batch := flag.Int("batch", 10, "batch count")
	flag.Parse()
	if *url == "" || !strings.HasPrefix(*url, "http") {
		fmt.Println("invalid url")
		os.Exit(1)
	}
	if *name == "" {
		fmt.Println("invalid name")
		os.Exit(1)
	}

	fmt.Println("filepath", *name)
	fd, err := os.Create(*name)
	if err != nil {
		fmt.Println("Create File:", err)
		os.Exit(1)
	}

	err = Download(*url, *batch, fd)
	if err != nil {
		fmt.Println("Download Failed:", err)
		os.Exit(1)
	}

	fmt.Println("download success!!!")
}

// ============================================ API ============================================

const (
	EXTINF = "EXTINF"
)

// https://cctvalih5ca.v.myalicdn.com/live/cctv2_2/index.m3u8
func Download(u string, batch int, fd io.Writer) error {
	lastIndex := strings.LastIndex(u, "/")
	endpoint := u[:lastIndex]
	raw, err := util.GET(u, nil)
	if err != nil {
		return err
	}

	tokens := strings.Split(string(raw), "\n")
	urls := make([]string, 0, 100)
	for idx := 0; idx < len(tokens); idx += 1 {
		token := strings.TrimSpace(tokens[idx])
		if len(token) == 0 {
			continue
		}

		if token[0] == '#' && strings.HasPrefix(token[1:], EXTINF) {
			u := strings.TrimSpace(tokens[idx+1])
			if strings.HasPrefix(u, "http") {
				urls = append(urls, u)
				idx += 1
			} else if strings.HasPrefix(u, "/") {
				urls = append(urls, endpoint+u)
				idx += 1
			} else {
				urls = append(urls, endpoint+"/"+u)
				idx += 1
			}
		}
	}

	download := func(u string) (data []byte, err error) {
		retry := 0
	try:
		raw, err := util.GET(u, nil)
		if err != nil && retry < 3 {
			fmt.Println("url:", u, "err:", err, "retry again")
			retry += 1
			goto try
		}
		if err != nil {
			fmt.Println("url:", u, "err:", err)
			return data, err
		}

		return raw, nil
	}

	var wg sync.WaitGroup
	step := batch
	for i := 0; i < len(urls); i += step {
		count := step
		if i+step >= len(urls) {
			count = len(urls) - i
		}

		data := make([][]byte, count)
		failed := false
		for k := 0; k < count; k++ {
			wg.Add(1)
			idx := k
			go func(idx int) {
				defer wg.Done()
				raw, err := download(urls[i+idx])
				if err != nil {
					failed = true
					return
				}
				data[idx] = raw
			}(idx)
		}
		wg.Wait()

		if failed {
			fmt.Println("download faild")
			os.Exit(1)
		}

		for i := range data {
			fd.Write(data[i])
		}
	}

	return nil
}
