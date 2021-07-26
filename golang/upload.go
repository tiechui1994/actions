package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)


/*
curl \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/tiechui1994/jobs/actions/workflows

curl -X POST \
  https://api.github.com/repos/tiechui1994/jobs/actions/workflows/ID/dispatches \
  -H 'Accept: application/vnd.github.v3+json' \
  -H 'Authorization: token TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
	"ref":"TAG|BRANCH",
    "inputs": {
        "name": "NAME",
        "url": "URL"
    }
  }'
*/

func main() {
	refresh := flag.String("t", "", "refresh token")
	dir := flag.String("d", "github", "save dir")
	file := flag.String("f", "", "file")
	flag.Parse()

	if *refresh == "" {
		fmt.Println("invalid token")
		os.Exit(1)
	}
	if *file == "" {
		fmt.Println("invalid file")
		os.Exit(1)
	}

	filename, err := filepath.Abs(*file)
	if err != nil {
		fmt.Println("invalid file error", err)
		os.Exit(1)
	}

	fmt.Println("filename:", filename)

	token, err := Refresh(*refresh)
	if err != nil {
		fmt.Println("refresh error", err)
		os.Exit(1)
	}

	files, err := Files("root", token)
	if err != nil {
		fmt.Println("files error", err)
		os.Exit(1)
	}

	var dirinfo File
	var exist bool
	for _, v := range files {
		if v.Name == *dir {
			exist = true
			dirinfo = v
			break
		}
	}
	if !exist {
		err = CreateDirectory(*dir, "root", token)
		if err != nil {
			fmt.Println("refresh error", err)
			return
		}
		files, err = Files("root", token)
		if err != nil {
			fmt.Println("files error", err)
			return
		}
		for _, v := range files {
			if v.Name == *dir {
				dirinfo = v
				break
			}
		}
	}

	err = UploadFile(filename, dirinfo.FileID, token)
	if err != nil {
		fmt.Println("upload file error", err)
		os.Exit(1)
	}

	err = UploadFile(filename+".SHA1", dirinfo.FileID, token)
	if err != nil {
		fmt.Println("upload sha1 file error", err)
	}

	fmt.Println("upload file sucess")
}
