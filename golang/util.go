package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"net/http"
	"net/http/cookiejar"
	"strings"
	"time"
)

type entry struct {
	Name       string    `json:"name"`
	Value      string    `json:"value"`
	Domain     string    `json:"domain"`
	Path       string    `json:"path"`
	SameSite   string    `json:"samesite"`
	Secure     bool      `json:"secure"`
	HttpOnly   bool      `json:"httponly"`
	Persistent bool      `json:"persistent"`
	HostOnly   bool      `json:"host_only"`
	Expires    time.Time `json:"expires"`
	Creation   time.Time `json:"creation"`
	LastAccess time.Time `json:"lastaccess"`
	SeqNum     uint64    `json:"seqnum"`
}

var (
	jar http.CookieJar
)

func init() {
	jar, _ = cookiejar.New(nil)
	http.DefaultClient = &http.Client{
		Transport: &http.Transport{
			DialContext: (&net.Dialer{
				Timeout:   30 * time.Second, //设置建立连接超时
				KeepAlive: 0,
			}).DialContext,
			DisableKeepAlives: true,
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
			},
			WriteBufferSize: 16 * 1024,
		},
		Jar:     jar,
		Timeout: 60 * time.Second,
	}
}

type CodeError int

func (err CodeError) Error() string {
	return http.StatusText(int(err))
}

func UserAgent() string {
	return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.164 Safari/537.36"
}

func request(method, u string, body interface{}, header map[string]string) (raw json.RawMessage, err error) {
	fmt.Println("api: => ", method, u)
	var reader io.Reader
	if body != nil {
		switch body.(type) {
		case io.Reader:
			reader = body.(io.Reader)
		case string:
			reader = strings.NewReader(body.(string))
		case []byte:
			reader = bytes.NewReader(body.([]byte))
		default:
			bin, _ := json.Marshal(body)
			fmt.Println("request: => ", string(bin))
			reader = bytes.NewReader(bin)
		}
	}

	request, _ := http.NewRequest(method, u, reader)
	if header != nil {
		for k, v := range header {
			request.Header.Set(k, v)
		}
	}
	request.Header.Set("user-agent", UserAgent())

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return raw, err
	}

	raw, err = ioutil.ReadAll(response.Body)
	if err != nil {
		return raw, err
	}

	fmt.Println("response: => ", response.StatusCode)

	if response.StatusCode >= 400 {
		return raw, CodeError(response.StatusCode)
	}

	return raw, nil
}

func POST(u string, body interface{}, header map[string]string) (raw json.RawMessage, err error) {
	return request("POST", u, body, header)
}

func PUT(u string, body interface{}, header map[string]string) (raw json.RawMessage, err error) {
	return request("PUT", u, body, header)
}

func GET(u string, header map[string]string) (raw json.RawMessage, err error) {
	return request("GET", u, nil, header)
}

func DELETE(u string, header map[string]string) (raw json.RawMessage, err error) {
	return request("DELETE", u, nil, header)
}
