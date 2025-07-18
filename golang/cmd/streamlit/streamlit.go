package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/tiechui1994/tool/util"
)

func main() {
	var endpoint = flag.String("endpoint", "", "streamlit endpoint")
	flag.Parse()
	if *endpoint == "" || !strings.HasSuffix(*endpoint, "streamlit.app") {
		log.Printf("invalid endpoint %v", *endpoint)
		os.Exit(1)
	}

	util.RegisterCookieJar(time.Now().Format("150405.000"))

	statusUrl := fmt.Sprintf("%s/api/v2/app/status", *endpoint)
	raw, err := util.GET(statusUrl, util.WithRetry(2), util.WithHeader(map[string]string{
		"origin": *endpoint,
	}))
	if err != nil {
		log.Printf("url %v request failed: %v", *endpoint, err)
		return
	}
	var status struct {
		Status int `json:"status"`
	}
	err = json.Unmarshal(raw, &status)
	if err != nil {
		log.Printf("%v decode %v failed: %v", *endpoint, string(raw), err)
		return
	}

	log.Printf("endpoint %v status: %v", *endpoint, status.Status)

	// status 5 is ok
	if status.Status == 5 {
		rand.Seed(time.Now().UnixNano())
		if rand.Float32() >= 0.4 {
			return
		}

		// random 40% execute
	}

	var token string
	withAfterResponse := util.WithAfterResponse(func(w *http.Response) {
		t := w.Header.Get("x-csrf-token")
		if t != "" {
			token = t
		}
	})
	withBeforeRequest := util.WithBeforeRequest(func(r *http.Request) {
		if token != "" {
			r.Header.Set("x-csrf-token", token)
		}
	})

	_, _ = util.GET(*endpoint, util.WithRetry(2), withBeforeRequest, withAfterResponse)
	_, _ = util.GET(statusUrl, util.WithRetry(2), util.WithHeader(map[string]string{
		"origin": *endpoint,
	}), withBeforeRequest, withAfterResponse)

	if status.Status != 5 {
		resumeUrl := fmt.Sprintf("%s/api/v2/app/resume", *endpoint)
		raw, err = util.POST(resumeUrl, util.WithRetry(2), util.WithHeader(map[string]string{
			"origin": *endpoint,
		}), withBeforeRequest, withAfterResponse)
		if err != nil {
			log.Printf("resume %v failure, %v %v", *endpoint, string(raw), err)
			os.Exit(1)
		}

		log.Printf("resume %v success", *endpoint)
	}

	log.Printf("login access %v success", *endpoint)
}
