package main

import (
	"crypto/md5"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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

// ============================================ API ============================================

const (
	yunpan = "https://api.aliyundrive.com"
)

var header = map[string]string{
	"accept":       "application/json",
	"content-type": "application/json",
}

func CalProof(accesstoken string, path string) string {
	// r := md5(accesstoken)[0:16]
	// i := size
	// 开始: r % i
	// 结束: min(开始+8, size)
	// 区间内容进行 Base64 转换
	info, _ := os.Stat(path)
	md := md5.New()
	md.Write([]byte(accesstoken))
	md5sum := hex.EncodeToString(md.Sum(nil))
	r, _ := strconv.ParseUint(md5sum[0:16], 16, 64)
	i := uint64(info.Size())
	o := r % i
	e := uint64(info.Size())
	if o+8 < e {
		e = o + 8
	}
	data := make([]byte, e-o)
	fd, _ := os.Open(path)
	fd.ReadAt(data, int64(o))

	return base64.StdEncoding.EncodeToString(data)
}

type Token struct {
	SboxDriveID  string `json:"default_sbox_drive_id"`
	DeviceID     string `json:"device_id"`
	DriveID      string `json:"default_drive_id"`
	UserID       string `json:"user_id"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func Refresh(refresh string) (token Token, err error) {
	u := yunpan + "/token/refresh"
	body := map[string]string{
		"refresh_token": refresh,
	}

	raw, err := POST(u, body, header)
	if err != nil {
		return token, err
	}

	err = json.Unmarshal(raw, &token)
	return token, err
}

//=====================================  file  =====================================

const (
	TYPE_FILE   = "file"
	TYPE_FOLDER = "folder"
)

type File struct {
	DriveID     string `json:"drive_id"`
	DomainID    string `json:"domain_id"`
	EncryptMode string `json:"encrypt_mode"`
	FileID      string `json:"file_id"`
	ParentID    string `json:"parent_file_id"`
	Type        string `json:"type"`
	Name        string `json:"name"`

	Size      int    `json:"size"`
	Category  string `json:"category"`
	Hash      string `json:"content_hash"`
	HashName  string `json:"content_hash_name"`
	Url       string `json:"download_url"`
	Thumbnail string `json:"thumbnail"`
	Extension string `json:"file_extension"`
}

func Files(fileid string, token Token) (list []File, err error) {
	u := yunpan + "/v2/file/list"
	header := map[string]string{
		"accept":        "application/json",
		"authorization": "Bearer " + token.AccessToken,
		"content-type":  "application/json",
	}
	var body struct {
		All                   bool   `json:"all"`
		DriveID               string `json:"drive_id"`
		Fields                string `json:"fields"`
		OrderBy               string `json:"order_by"`
		OrderDirection        string `json:"order_direction"`
		Limit                 int    `json:"limit"`
		ParentFileID          string `json:"parent_file_id"`
		UrlExpireSec          int    `json:"url_expire_sec"`
		ImageUrlProcess       string `json:"image_url_process"`
		ImageThumbnailProcess string `json:"image_thumbnail_process"`
		VideoThumbnailProcess string `json:"video_thumbnail_process"`
	}

	body.DriveID = token.DriveID
	body.Fields = "*"
	body.OrderBy = "updated_at"
	body.OrderDirection = "DESC"
	body.Limit = 100
	body.ParentFileID = fileid
	body.UrlExpireSec = 1600
	body.ImageUrlProcess = "image/resize,w_1920/format,jpeg"
	body.ImageThumbnailProcess = "image/resize,w_400/format,jpeg"
	body.VideoThumbnailProcess = "video/snapshot,t_0,f_jpg,ar_auto,w_800"
	raw, err := POST(u, body, header)
	if err != nil {
		return list, err
	}

	var result struct {
		Items      []File `json:"items"`
		NextMarker string `json:"next_marker"`
	}

	err = json.Unmarshal(raw, &result)
	if err != nil {
		return list, err
	}

	return result.Items, nil
}

type UploadFolderInfo struct {
	DeviceID     string `json:"device_id"`
	DomainID     string `json:"domain_id"`
	FileID       string `json:"file_id"`
	ParentID     string `json:"parent_file_id"`
	Type         string `json:"type"`
	Name         string `json:"file_name"`
	UploadID     string `json:"upload_id"`
	RapidUpload  bool   `json:"rapid_upload"`
	PartInfoList []struct {
		InternalUploadUrl string `json:"internal_upload_url"`
		PartNumber        int    `json:"part_number"`
		UploadUrl         string `json:"upload_url"`
	} `json:"part_info_list"`
}

const (
	refuse_mode = "refuse"
	rename_mode = "auto_rename"
)

func CreateWithFolder(checkmode, name, filetype, fileid string, token Token, appendargs map[string]interface{}, path ...string) (
	upload UploadFolderInfo, err error) {
	u := yunpan + "/adrive/v2/file/createWithFolders"
	header := map[string]string{
		"accept":        "application/json",
		"authorization": "Bearer " + token.AccessToken,
		"content-type":  "application/json",
	}

	body := map[string]interface{}{
		"check_name_mode": checkmode,
		"drive_id":        token.DriveID,
		"name":            name,
		"parent_file_id":  fileid,
		"type":            filetype,
	}

	if appendargs != nil {
		for k, v := range appendargs {
			body[k] = v
		}
	}

	raw, err := POST(u, body, header)
	if err != nil {
		// pre_hash match
		if val, ok := err.(CodeError); ok && val == http.StatusConflict {
			if len(path) == 0 {
				return upload, errors.New("no path")
			}
			buf := make([]byte, 10*1024*1024)
			sh := sha1.New()
			fd, err := os.Open(path[0])
			if err != nil {
				return upload, err
			}
			_, err = io.CopyBuffer(sh, fd, buf)
			if err != nil {
				return upload, err
			}

			args := map[string]interface{}{
				"size":              appendargs["size"],
				"part_info_list":    appendargs["part_info_list"],
				"proof_version":     "v1",
				"proof_code":        CalProof(token.AccessToken, path[0]),
				"content_hash_name": "sha1",
				"content_hash":      strings.ToUpper(hex.EncodeToString(sh.Sum(nil))),
			}
			return CreateWithFolder(checkmode, name, filetype, fileid, token, args)
		}

		return upload, err
	}

	err = json.Unmarshal(raw, &upload)
	return upload, err
}

func UploadFile(path, fileid string, token Token) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	fd, err := os.Open(path)
	if err != nil {
		return err
	}

	data := make([]byte, 1024) // 1K, prehash
	fd.Read(data)
	sh := sha1.New()
	sh.Write(data)
	prehash := hex.EncodeToString(sh.Sum(nil))

	m10 := 10 * 1024 * 1024 // 10M
	part := int(info.Size()) / m10
	if int(info.Size())%m10 != 0 {
		part += 1
	}

	var partlist []map[string]int
	for i := 1; i <= part; i++ {
		partlist = append(partlist, map[string]int{"part_number": i})
	}
	args := map[string]interface{}{
		"pre_hash":       prehash,
		"size":           info.Size(),
		"part_info_list": partlist,
	}
	upload, err := CreateWithFolder(rename_mode, info.Name(), TYPE_FILE, fileid, token, args, path)
	if err != nil {
		return err
	}

	if upload.RapidUpload {
		return nil
	}

	data = make([]byte, m10)
	for _, part := range upload.PartInfoList {
		u := part.UploadUrl
		n := part.PartNumber
		nw, _ := fd.ReadAt(data, int64((n-1)*m10))
		_, err = PUT(u, data[:nw], nil)
		if err != nil {
			return err
		}
	}

	u := yunpan + "/v2/file/complete"
	header := map[string]string{
		"accept":        "application/json",
		"authorization": "Bearer " + token.AccessToken,
		"content-type":  "application/json",
	}
	body := map[string]string{
		"drive_id":  token.DriveID,
		"file_id":   upload.FileID,
		"upload_id": upload.UploadID,
	}
	_, err = POST(u, body, header)
	return err
}

func CreateDirectory(name, fileid string, token Token) (err error) {
	_, err = CreateWithFolder(refuse_mode, name, TYPE_FOLDER, fileid, token, nil)
	return err
}
