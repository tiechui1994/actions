package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
	ffprobe := flag.String("ffprobe", "", "ffprobe PATH")
	ffmpeg := flag.String("ffmpeg", "", "ffprobe PATH")
	flag.Parse()

	if *u == "" {
		fmt.Println("invalid url")
		os.Exit(1)
	}
	if *name == "" {
		fmt.Println("invalid name")
		os.Exit(1)
	}
	if !*audio && (*ffmpeg == "" || *ffprobe == "") {
		fmt.Println("invalid ffmpeg/ffprobe")
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
			speech.WithVideoOnly,
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
	filePath := fmt.Sprintf("%v.%v", *name, format.SubType)
	fmt.Printf("chouice quality: %vP, FPS: %v\n", *quality, *fps)
	fmt.Printf("really quality: %v, FPS: %v\n", format.Res, format.Fps)
	fmt.Printf("filepath: %v\n", filePath)
	fmt.Printf("url: %v\n", format.Url)

	err = format.Download(filePath)
	if err != nil {
		fmt.Println("Download Failed.", err)
		os.Exit(1)
	}

	if !*audio {
		command := fmt.Sprintf("%v -v quiet -print_format json -show_streams %v", *ffprobe, filePath)
		cmd := exec.Command("bash", "-c", command)
		raw, err := cmd.Output()
		if err != nil {
			fmt.Println("ffprobe Failed.", err)
			os.Exit(1)
		}
		var result struct {
			Streams []map[string]interface{} `json:"streams"`
		}
		_ = json.Unmarshal(raw, &result)

		var videoCodec string
		for _, v := range result.Streams {
			if v["codec_type"] == "video" {
				videoCodec = v["codec_name"].(string)
			}
		}

		if len(result.Streams) == 1 {
			yt := speech.YouTube{VideoID: strings.TrimSpace(values[0][1])}
			audioFormat, err := yt.Filter(speech.WithAudioOnly).First()
			if err != nil {
				fmt.Println("query audio not exist: ", err)
				os.Exit(1)
			}

			dir, fileName := filepath.Split(*name)

			audioPath := filepath.Join(dir, fmt.Sprintf("audio_%v.%v", fileName, audioFormat.SubType))
			defer os.Remove(audioPath)
			err = audioFormat.Download(audioPath)
			if err != nil {
				fmt.Println("Download Audio Failed.", err)
				os.Exit(1)
			}

			videoPath := filepath.Join(dir, fmt.Sprintf("video_%v.%v", fileName, format.SubType))
			_ = os.Rename(filePath, videoPath)
			defer os.Remove(videoPath)

			var command string
			switch videoCodec {
			case "vp9":
				filePath = fmt.Sprintf("%v.%v", *name, format.SubType)
				command = fmt.Sprintf("%v -v info -i %v -i %v -threads 4 -c:v copy -c:a libopus %v", *ffmpeg, videoPath, audioPath, filePath)
			case "h264":
				filePath = fmt.Sprintf("%v.%v", *name, format.SubType)
				command = fmt.Sprintf("%v -v info -i %v -i %v -threads 4 -c:v copy -c:a aac %v", *ffmpeg, videoPath, audioPath, filePath)
			case "mpeg4":
				filePath = fmt.Sprintf("%v.%v", *name, format.SubType)
				command = fmt.Sprintf("%v -v info -i %v -i %v -threads 4 -c:v copy -map 0:v -map 1:a %v", *ffmpeg, videoPath, audioPath, filePath)
			case "mpeg2video":
				filePath = fmt.Sprintf("%v.%v", *name, format.SubType)
				command = fmt.Sprintf("%v -v info -i %v -i %v -threads 4 -c:v copy -c:a mp2 %v", *ffmpeg, videoPath, audioPath, filePath)
			default:
				filePath = fmt.Sprintf("%v.mp4", *name)
				command = fmt.Sprintf("%v -v info -i %v -i %v -threads 4 -c:v h264 -c:a aac -f mp4 %v", *ffmpeg, videoPath, audioPath, filePath)
			}

			fmt.Println("Combine Video and Audio: ", command)
			cmd := exec.Command("bash", "-c", command)
			cmd.Stderr = os.Stderr
			cmd.Stdout = os.Stdout
			err = cmd.Run()
			if err != nil {
				fmt.Println("Combined Failed.", err)
				os.Exit(1)
			}
		}
	}

	fmt.Println("Download Success, file size:", fmt.Sprintf("%0.2f MB", float64(format.FileSize)/(1024.0*1024.0)))
}
