package main

import (
	"flag"
	"fmt"
	"path/filepath"
)


/*
curl \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/tiechui1994/jobs/actions/workflows

curl \
  -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/tiechui1994/jobs/actions/workflows/11604575/dispatches \
  -d '{"name":"xx", "url":"xx"}'
*/

func main() {
	refresh := flag.String("t", "", "refresh token")
	dir := flag.String("d", "github", "save dir")
	file := flag.String("f", "", "file")
	flag.Parse()

	if *refresh == "" {
		fmt.Println("invalid token")
		return
	}
	if *file == "" {
		fmt.Println("invalid file")
		return
	}

	filename, err := filepath.Abs(*file)
	if err != nil {
		fmt.Println("invalid file error", err)
		return
	}

	fmt.Println("filename:", filename)

	token, err := Refresh(*refresh)
	if err != nil {
		fmt.Println("refresh error", err)
		return
	}

	files, err := Files("root", token)
	if err != nil {
		fmt.Println("files error", err)
		return
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
		return
	}

	fmt.Println("upload file sucess")
}
