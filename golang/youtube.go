package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math/rand"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tiechui1994/tool/util"
)

const (
	SiteDownloader = "youtube4kdownloader"
	SiteSaveTube   = "save.tube"
)

func random(size int) string {
	rand.Seed(time.Now().UnixNano())
	str := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	result := make([]byte, size)
	for i := 0; i < size; i++ {
		result[i] = str[int(rand.Int31n(int32(len(str))))]
	}

	return string(result)
}

func GetUrl(site, youtube string) string {
	values := make(url.Values)
	values.Add("video", youtube)
	values.Add("rand", random(15))

	switch site {
	case SiteSaveTube:
		return "https://s4.save.tube/ajax/getLinks.php?" + values.Encode()
	default:
		return "https://youtube4kdownloader.com/ajax/getLinks.php?" + values.Encode()
	}
}

type Quality int

func (q *Quality) UnmarshalText(text []byte) error {
	if len(text) > 0 && text[len(text)-1] == 'p' {
		value := string(text[:len(text)-1])
		v, err := strconv.ParseUint(value, 10, 64)
		if err != nil {
			return err
		}
		*q = Quality(v)
	}

	return nil
}

type Vedio struct {
	Ext     string          `json:"ext"`
	FPS     int             `json:"fps"`
	Fid     int             `json:"fid"`
	Quality Quality         `json:"quality"`
	Url     string          `json:"url"`
	Size    json.RawMessage `json:"size"`
	size    int
}

type Audio struct {
	Acodec string          `json:"acodec"`
	Abr    string          `json:"abr"`
	Asr    int             `json:"asr"`
	Ext    string          `json:"ext"`
	Url    string          `json:"url"`
	Size   json.RawMessage `json:"size"`
	size   int
}

func (a *Vedio) GetSize() int {
	if a.size != 0 {
		return a.size
	}
	if len(a.Size) > 0 {
		json.Unmarshal(a.Size, &a.size)
	} else {
		a.size = -1
	}
	return a.size
}

func (a *Audio) GetSize() int {
	if a.size != 0 {
		return a.size
	}
	if len(a.Size) > 0 {
		json.Unmarshal(a.Size, &a.size)
	} else {
		a.size = -1
	}

	return a.size
}

func GetVedios(url string) (vedio []Vedio, audio []Audio, err error) {
	raw, err := util.GET(url, map[string]string{})
	if err != nil {
		return
	}

	var resonse struct {
		Data struct {
			Title string  `json:"title"`
			Av    []Vedio `json:"av"`
			A     []Audio `json:"a"`
		}
		Status string `json:"status"`
	}

	err = json.Unmarshal(raw, &resonse)
	if err != nil {
		fmt.Println(err)
		return
	}

	if resonse.Status != "success" {
		err = errors.New(string(raw))
		return
	}

	var u string
	for i := range resonse.Data.Av {
		if strings.Contains(resonse.Data.Av[i].Url, "[[_index_]]") {
			u = resonse.Data.Av[i].Url
			break
		}
	}
	for i := range resonse.Data.Av {
		resonse.Data.Av[i].Url = strings.Replace(u, "[[_index_]]", fmt.Sprintf("%v", i), 1)
	}

	for i := range resonse.Data.A {
		if strings.Contains(resonse.Data.A[i].Url, "[[_index_]]") {
			u = resonse.Data.A[i].Url
			break
		}
	}
	for i := range resonse.Data.A {
		resonse.Data.A[i].Url = strings.Replace(u, "[[_index_]]", fmt.Sprintf("%v", i), 1)
	}

	sort.SliceIsSorted(resonse.Data.Av, func(i, j int) bool {
		if resonse.Data.Av[i].Quality != resonse.Data.Av[j].Quality {
			return resonse.Data.Av[i].Quality > resonse.Data.Av[j].Quality
		}
		if resonse.Data.Av[i].FPS != resonse.Data.Av[j].FPS {
			return resonse.Data.Av[i].FPS > resonse.Data.Av[j].FPS
		}
		return resonse.Data.Av[i].Fid < resonse.Data.Av[j].Fid
	})

	return resonse.Data.Av, resonse.Data.A, nil
}

func main() {
	quality := flag.Int("quality", 720, "Vedio Quality")
	fps := flag.Int("fps", 30, "Vedio FPS")
	name := flag.String("name", "", "Save Vedio Name")
	u := flag.String("url", "", "YouTube Download URL")
	flag.Parse()

	if *u == "" {
		fmt.Println("invalid url")
		os.Exit(1)
	}
	if *name == "" {
		fmt.Println("invalid name")
		os.Exit(1)
	}

	retry := 0
	site := SiteSaveTube
try:
	vedios, _, err := GetVedios(GetUrl(site, *u))
	if err != nil || len(vedios) == 0 {
		if retry < 3 {
			retry += 1
			if site == SiteDownloader {
				site = SiteSaveTube
			} else {
				site = SiteDownloader
			}
			time.Sleep(time.Second * 2)
			goto try
		}
		fmt.Println("Get Vedios failed.", err)
		os.Exit(1)
	}

	var (
		index     = -1
		firstFind = -1
	)
	for idx, vedio := range vedios {
		if int(vedio.Quality) == *quality && vedio.FPS >= *fps {
			index = idx
			break
		}
		if int(vedio.Quality) == *quality && firstFind == -1 {
			firstFind = idx
		}
	}

	var vedio Vedio
	if index != -1 {
		vedio = vedios[index]
	} else if firstFind != -1 {
		vedio = vedios[firstFind]
	} else {
		vedio = vedios[0]
	}

	filepath := fmt.Sprintf("%v.%v", *name, vedio.Ext)

	fmt.Printf("chouice quality: %vP, FPS: %v\n", *quality, *fps)
	fmt.Printf("really quality: %vP, FPS: %v\n", vedio.Quality, vedio.FPS)
	fmt.Printf("filepath: %v\n", filepath)
	fmt.Printf("url: %v\n", vedio.Url)

	reader, err := util.File(vedio.Url, "GET", nil, nil)
	if err != nil {
		fmt.Println("Get Vedios failed.", err)
		os.Exit(1)
	}

	writer, _ := os.Create(filepath)
	go func() {
		timer := time.NewTicker(10 * time.Second)
		start := time.Now()
		last := 0.0
		for range timer.C {
			info, _ := writer.Stat()
			current := float64(info.Size())

			if vedio.GetSize() > 0 {
				fmt.Printf("%ds download: %0.3f%% current size: %vMiB .... speed: %0.3fMiB/s \n",
					int(time.Now().Sub(start).Seconds()), current*100.0/float64(vedio.GetSize()),
					int(current/(1024*1024)), (current-last)/(10.0*1024*1024))
			} else {
				fmt.Printf("%ds current size: %vMiB .... speed: %0.3fMiB/s \n",
					int(time.Now().Sub(start).Seconds()),
					int(current/(1024*1024)), (current-last)/(10.0*1024*1024))
			}

			last = current
		}
	}()
	n, err := io.CopyBuffer(writer, reader, make([]byte, 1024*1024*8))
	if err != nil {
		fmt.Println("Download Failed.", err)
		os.Exit(1)
	}

	fmt.Println("Download Success, file size:", fmt.Sprintf("%0.2f MB", float64(n)/(1024.0*1024.0)))
}