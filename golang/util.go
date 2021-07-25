package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"strings"
)

type CodeError int

func (err CodeError) Error() string {
	return http.StatusText(int(err))
}

func UserAgent() string {
	return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.164 Safari/537.36"
}

func request(method, u string, body interface{}, header map[string]string) (raw json.RawMessage, err error) {
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

	fmt.Println("response: => ", response.StatusCode, string(raw))

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
