package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/tiechui1994/tool/speech"
)

func main() {
	audio := flag.Bool("audio", false, "audio")
	quality := flag.Int("quality", 720, "video Quality")
	fps := flag.Int("fps", 30, "video FPS")
	name := flag.String("name", "", "save file name")
	u := flag.String("url", "", "youtube download URL")
	flag.Parse()

	if *u == "" {
		fmt.Println("invalid url")
		os.Exit(1)
	}
	if *name == "" {
		fmt.Println("invalid name")
		os.Exit(1)
	}

	r := regexp.MustCompile(`https://www\.youtube\.com/watch\?v=(.*)`)
	values := r.FindAllStringSubmatch(*u, 1)
	if len(values) < 0 || len(values[0]) < 2 {
		fmt.Printf("invalid url: %v \n", *u)
		os.Exit(1)
	}

	var format speech.Format
	var err error
	yt := speech.YouTube{VideoID: strings.TrimSpace(values[0][1])}
	if *audio {
		format, err = yt.Filter(speech.WithAudioOnly).First()
	} else {
		format, err = yt.Filter(
			func(format speech.Format) bool {
				var val int64
				if strings.HasSuffix(format.Res, "p") {
					val, _ = strconv.ParseInt(format.Res[:len(format.Res)-1], 10, 64)
				}
				return val >= int64(*quality) && format.Fps >= *fps
			},
		).OrderBy(speech.QualityOrder).Last()
	}
	if err != nil {
		fmt.Println("query audio/video not exist: ", err)
		os.Exit(1)
	}

	filepath := fmt.Sprintf("%v.%v", *name, format.SubType)
	fmt.Printf("chouice quality: %vP, FPS: %v\n", *quality, *fps)
	fmt.Printf("really quality: %v, FPS: %v\n", format.Res, format.Fps)
	fmt.Printf("filepath: %v\n", filepath)
	fmt.Printf("url: %v\n", format.Url)

	err = format.Download(filepath)
	if err != nil {
		fmt.Println("Download Failed.", err)
		os.Exit(1)
	}

	fmt.Println("Download Success, file size:", fmt.Sprintf("%0.2f MB", float64(format.FileSize)/(1024.0*1024.0)))
}
