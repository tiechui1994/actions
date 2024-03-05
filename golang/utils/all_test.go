package utils

import (
	"io/fs"
	"path/filepath"
	"testing"
)

func TestBruteForce(t *testing.T) {
	filepath.Walk(".", func(path string, info fs.FileInfo, err error) error {
		t.Logf("%v", path)
		return err
	})
}
