package utils

import (
	"bytes"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/yeka/zip"
)

func GenerateCombinationsString(data []string, length int) <-chan []string {
	c := make(chan []string)
	go func(c chan []string) {
		defer close(c)
		combosString(c, []string{}, data, length)
	}(c)
	return c
}

func combosString(c chan []string, combo []string, data []string, length int) {
	if length <= 0 {
		return
	}
	var newCombo []string
	for _, ch := range data {
		newCombo = append(combo, ch)
		if length == 1 {
			output := make([]string, len(newCombo))
			copy(output, newCombo)
			c <- output
		}
		combosString(c, newCombo, data, length-1)
	}
}

func unzip(filename string, password string, distDir string) bool {
	r, err := zip.OpenReader(filename)
	if err != nil {
		return false
	}
	defer r.Close()

	buf := make([]byte, 4096)

	decrypt := func(zipFile *zip.File, password string, buffer io.Writer) error {
		zipFile.SetPassword(password)
		reader, err := zipFile.Open()
		if err != nil {
			return err
		}

		n, err := io.CopyBuffer(buffer, reader, buf)
		if n == 0 || err != nil {
			return fmt.Errorf("error: %w", err)
		}

		return nil
	}

	buffer := new(bytes.Buffer)
	if len(r.File) > 0 {
		err = decrypt(r.File[0], password, buffer)
		if err != nil {
			return false
		}

		// 解压文件
		f := r.File[0]
		filename := filepath.Join(distDir, f.Name)
		_ = os.MkdirAll(filepath.Dir(filename), 0777)
		_ = ioutil.WriteFile(filename, buffer.Bytes(), f.Mode())

		for i := 1; i < len(r.File); i++ {
			f := r.File[i]
			if f.Mode().IsDir() {
				continue
			}

			filename := filepath.Join(distDir, f.Name)
			_ = os.MkdirAll(filepath.Dir(filename), 0777)
			fd, err := os.OpenFile(filename, os.O_CREATE|os.O_APPEND|os.O_RDWR|os.O_SYNC, f.Mode())
			if err != nil {
				continue
			}

			err = decrypt(f, password, fd)
			if err != nil {
				log.Printf("decrypt: %v", err)
			}
			fd.Close()
		}
	}

	return true
}

func BruteForce(zipFile string, distDir string, alphabet []string) error {
	for i := 1; i <= 10; i++ {
		for combo := range GenerateCombinationsString(alphabet, i) {
			res := unzip(zipFile, strings.Join(combo, ""), distDir)
			if res == true {
				log.Printf("Password matched: %s", strings.Join(combo, ""))
				return nil
			}
		}
	}

	return fmt.Errorf("not found password")
}
