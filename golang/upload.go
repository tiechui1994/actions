package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tiechui1994/tool/aliyun"
	"github.com/tiechui1994/tool/util"
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
	upload := flag.Bool("upload", false, "upload file")
	remove := flag.Bool("delete", false, "delete file")
	dir := flag.String("dir", "github", "want to save dir")
	file := flag.String("file", "", "file name")
	fileid := flag.String("fileid", "", "yunpan fileid")
	flag.Parse()

	token, err := Get()
	if err != nil {
		fmt.Println("refresh error", err)
		os.Exit(1)
	}

	if *upload {
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
		handleUpload(token, *dir, filename)
	} else if *remove {
		if *fileid == "" || len(*fileid) != 40 {
			fmt.Println("invalid fileid")
			os.Exit(1)
		}

		handleDelete(token, *fileid)
	}
}

func handleDelete(token aliyun.Token, fileid string) {
	err := aliyun.Delete([]aliyun.File{
		{
			DriveID: token.DriveID,
			FileID:  fileid,
		},
	}, token)
	if err != nil {
		fmt.Println("Delete error", err)
		os.Exit(1)
	}

	fmt.Println("delete file success")
}

func handleUpload(token aliyun.Token, dir, filename string) {
	files, err := aliyun.Files("root", token)
	if err != nil {
		fmt.Println("Files:", err)
		os.Exit(1)
	}

	var dirFile aliyun.File
	var exist bool
	for _, v := range files {
		if v.Name == dir {
			exist = true
			dirFile = v
			break
		}
	}
	if !exist {
		upload, err := aliyun.CreateDirectory(dir, "root", token)
		if err != nil {
			fmt.Println("CreateDirectory:", err)
			return
		}
		dirFile.FileID = upload.FileID
	}

	_, err = aliyun.UploadFile(filename, dirFile.FileID, token)
	if err != nil {
		fmt.Println("UploadFile:", err)
		os.Exit(1)
	}

	_, err = aliyun.UploadFile(filename+".SHA1", dirFile.FileID, token)
	if err != nil {
		fmt.Println("UploadFile:", err, filename+".SHA1")
	}

	fmt.Println("upload file sucess")
}

func Get() (token aliyun.Token, err error) {
	u := "https://jobs.tiechui1994.tk/api/aliyun?response_type=refresh_token&key=yunpan"
	retry := 0
tryagin:
	raw, err := util.GET(u, nil)
	if _, ok := err.(util.CodeError); ok && retry < 4 {
		retry += 1
		goto tryagin
	}
	if err != nil {
		return token, err
	}

	err = json.Unmarshal(raw, &token)
	return token, err
}
