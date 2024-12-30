package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"regexp"

	"github.com/tiechui1994/tool/util"
)

func fetchGo(goVersion string) error {
	u := fmt.Sprintf("https://go.dev/dl/%v.linux-amd64.tar.gz", goVersion)
	fmt.Println("start download", goVersion, u, ".....")
	reader, err := util.File(u, http.MethodGet, util.WithRetry(2))
	if err != nil {
		return err
	}
	tmpName := fmt.Sprintf("/tmp/%v.tar.gz", goVersion)
	writer, err := os.Create(tmpName)
	if err != nil {
		return err
	}
	_, err = io.CopyBuffer(writer, reader, make([]byte, 8192))
	if err != nil {
		return err
	}

	cmd := fmt.Sprintf(`rm -rf /opt/go && tar xf %v -C /opt && /opt/go/bin/go env -w GOPATH=/tmp/go GOPROXY=direct GOFLAGS="-insecure"`, tmpName)
	command := exec.Command("bash", "-c", cmd)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}

func build(goUrl, version, distPath, name, goarch, goVersion string) error {
	fmt.Println("start build ", goarch, name, version, ".....")
	goUrl = fmt.Sprintf("%v@%v", goUrl, version)

	srcPath := fmt.Sprintf("/tmp/go/bin/%v", name)
	if goarch == "arm64" {
		srcPath = fmt.Sprintf("/tmp/go/bin/linux_arm64/%v", name)
	}

	r := regexp.MustCompile(`(1.2[0-9]|1.1[0-9]|1.[0-9])`)
	if r.MatchString(goVersion) {
		t := r.FindAllStringSubmatch(goVersion, 1)
		goVersion = t[0][1]
	}

	distPath = path.Join(distPath, fmt.Sprintf("%v-%v-%v-%v", name, goarch, version, goVersion))

	cmd := fmt.Sprintf("GOOS=%v GOARCH=%v CGO_ENABLED=0 /opt/go/bin/go install %v", "linux", goarch, goUrl)
	command := exec.Command("bash", "-c", cmd)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	err := command.Run()
	if err != nil {
		return err
	}

	cmd = fmt.Sprintf("cp %v %v", srcPath, distPath)
	command = exec.Command("bash", "-c", cmd)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}

type multiValue []string

func (v *multiValue) Set(s string) error {
	*v = append(*v, s)
	return nil
}

func (v *multiValue) Get() interface{} {
	return *v
}

func (v *multiValue) String() string {
	return ""
}

func main() {
	goList := &multiValue{}
	archList := &multiValue{}
	flag.Var(goList, "go", "go version")
	flag.Var(archList, "arch", "build arch")
	name := flag.String("name", "", "build command name")
	version := flag.String("version", "", "build command version")
	goUrl := flag.String("url", "", "github command url")
	dist := flag.String("dist", ".", "build dist")
	flag.Parse()

	for _, goVersion := range *goList {
		err := fetchGo(goVersion)
		if err != nil {
			fmt.Println("fetch go version failed:", goVersion, err)
			os.Exit(1)
		}

		for _, arch := range *archList {
			err := build(*goUrl, *version, *dist, *name, arch, goVersion)
			if err != nil {
				fmt.Println("build go version failed:", goVersion, err)
				os.Exit(1)
			}
		}
	}
}
