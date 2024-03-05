package utils

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/ioutil"

	"github.com/tiechui1994/tool/util"
)

func UploadFile(file string) (string, error) {
	u := "https://api.vercel.com/v2/now/files"

	raw, _ := ioutil.ReadFile(file)
	hash := sha1.New()
	hash.Write(raw)

	sha1Digest := hex.EncodeToString(hash.Sum(nil))
	raw, err := util.POST(u, util.WithHeader(map[string]string{
		"Authorization":  "Bearer " + "kmv26RuRl0cj2jkKY3u7jzuL",
		"Content-Length": fmt.Sprintf("%v", len(raw)),
		"x-now-digest":   sha1Digest,
	}), util.WithBody(raw))
	if err != nil {
		return "", err
	}

	fmt.Println(string(raw))

	var result struct {
		Error json.RawMessage `json:"error"`
		URLs  []string        `json:"urls"`
	}
	err = json.Unmarshal(raw, &result)
	if err != nil {
		return "", err
	}

	if len(result.URLs) == 0 {
		return fmt.Sprintf("https://dmmcy0pwk6bqi.cloudfront.net/%v", sha1Digest), nil
	}

	return result.URLs[0], nil
}
