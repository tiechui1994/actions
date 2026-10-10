package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/tiechui1994/tool/util"
)

func TestIIILabFooter(t *testing.T) {
	got := iiiLabFooter("https://youtu.be/test", "1700000000000")
	const want = "97ae585a6ea6c87425af9e225aa03307"
	if got != want {
		t.Fatalf("iiiLabFooter() = %q, want %q", got, want)
	}
}

func TestVideoProxyAppliesToHTTPAndUtilRequests(t *testing.T) {
	proxyRequests := 0
	proxyServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		proxyRequests++
		if !r.URL.IsAbs() || r.URL.Host != "origin.example" {
			t.Errorf("proxy received request URL %q, want absolute URL for origin.example", r.URL)
		}
		if r.URL.Path == "/api" {
			_, _ = io.WriteString(w, `{"proxied":true}`)
			return
		}
		_, _ = io.WriteString(w, "proxied")
	}))
	defer proxyServer.Close()

	if err := configureVideoProxy(proxyServer.URL); err != nil {
		t.Fatalf("configureVideoProxy() error = %v", err)
	}
	t.Cleanup(func() { _ = configureVideoProxy("") })

	resp, err := newVideoHTTPClient(time.Second).Get("http://origin.example/video")
	if err != nil {
		t.Fatalf("HTTP client request failed: %v", err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatalf("failed to read HTTP client response: %v", err)
	}
	if string(body) != "proxied" {
		t.Errorf("HTTP client response = %q, want proxied", body)
	}

	apiBody, err := videoUtilGet("http://origin.example/api", util.WithRetry(0))
	if err != nil {
		t.Fatalf("util GET request failed: %v", err)
	}
	if string(apiBody) != `{"proxied":true}` {
		t.Errorf("util GET response = %s, want proxied JSON", apiBody)
	}
	if proxyRequests != 2 {
		t.Errorf("proxy received %d requests, want 2", proxyRequests)
	}
}

func TestFromAPI(t *testing.T) {
	v, err := extractVideoFormatsFromAPI("https://www.youtube.com/watch?v=Mqn6dOKoMQg")
	if err != nil {
		t.Fatalf("extractVideoFormatsFromAPI() error = %v", err)
	}
	if len(v) == 0 {
		t.Fatal("no video formats extracted")
	}
	for _, q := range v {
		t.Log("URL:", q.URL)
		t.Log("AudioURL:", q.AudioURL)
	}
}

func TestExtractVideoFormatsFromAPI(t *testing.T) {
	videoURL := "https://www.youtube.com/watch?v=Mqn6dOKoMQg"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("request method = %q, want POST", r.Method)
		}

		var payload map[string]string
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("failed to decode request payload: %v", err)
		}
		if payload["url"] != videoURL || payload["site"] != "youtube" {
			t.Errorf("request payload = %#v, want URL %q and site youtube", payload, videoURL)
		}

		timestamp := r.Header.Get("G-Timestamp")
		if _, err := strconv.ParseInt(timestamp, 10, 64); err != nil {
			t.Errorf("G-Timestamp = %q, want Unix milliseconds", timestamp)
		}
		if got, want := r.Header.Get("G-Footer"), iiiLabFooter(videoURL, timestamp); got != want {
			t.Errorf("G-Footer = %q, want %q", got, want)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"id":"Mqn6dOKoMQg","medias":[{"media_type":"video","formats":[{"quality":1080,"quality_label":"1080p","video_url":"https://cdn.example/video.mp4","audio_url":"https://cdn.example/audio.m4a","video_ext":"mp4","video_filesize":1234}]},{"media_type":"audio","resource_url":"https://cdn.example/audio.m4a"}]}`)
	}))
	defer server.Close()

	qualities, err := extractVideoFormatsFromAPIWithClient(videoURL, server.URL, server.Client())
	if err != nil {
		t.Fatalf("extractVideoFormatsFromAPIWithClient() error = %v", err)
	}
	if len(qualities) != 1 {
		t.Fatalf("got %d formats, want 1", len(qualities))
	}
	want := VideoQuality{
		Quality:  "1080p",
		Height:   1080,
		URL:      "https://cdn.example/video.mp4",
		AudioURL: "https://cdn.example/audio.m4a",
		MimeType: "video/mp4",
		FileSize: 1234,
	}
	if qualities[0] != want {
		t.Errorf("format = %#v, want %#v", qualities[0], want)
	}
}

func TestDownloadChunkRetriesTransientFailure(t *testing.T) {
	data := []byte("chunk-data")
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests == 1 {
			http.Error(w, "temporary failure", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Range", fmt.Sprintf("bytes 0-%d/%d", len(data)-1, len(data)))
		w.WriteHeader(http.StatusPartialContent)
		_, _ = w.Write(data)
	}))
	defer server.Close()

	partsDir := t.TempDir()
	if err := downloadChunk(server.Client(), server.URL, partsDir, 0, int64(len(data))); err != nil {
		t.Fatalf("downloadChunk() error = %v", err)
	}
	if requests != 2 {
		t.Errorf("chunk requested %d times, want retry then success", requests)
	}

	got, err := os.ReadFile(filepath.Join(partsDir, "00000000.part"))
	if err != nil {
		t.Fatalf("failed to read downloaded chunk: %v", err)
	}
	if !bytes.Equal(got, data) {
		t.Errorf("downloaded chunk = %q, want %q", got, data)
	}
}

func TestDownloadFileResumesCompletedChunks(t *testing.T) {
	data := bytes.Repeat([]byte("v"), int(downloadChunkSize+17))
	var mu sync.Mutex
	firstChunkRequests := 0
	secondChunkRequests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var start, end int64
		if _, err := fmt.Sscanf(r.Header.Get("Range"), "bytes=%d-%d", &start, &end); err != nil {
			http.Error(w, "missing range", http.StatusBadRequest)
			return
		}
		if end >= int64(len(data)) {
			end = int64(len(data)) - 1
		}

		mu.Lock()
		if start == 0 && end == 0 {
			w.Header().Set("Content-Range", fmt.Sprintf("bytes 0-0/%d", len(data)))
			w.WriteHeader(http.StatusPartialContent)
			_, _ = w.Write(data[:1])
			mu.Unlock()
			return
		}
		if start == 0 {
			firstChunkRequests++
		} else {
			secondChunkRequests++
			if secondChunkRequests <= downloadChunkMaxAttempts {
				mu.Unlock()
				http.Error(w, "temporary failure", http.StatusServiceUnavailable)
				return
			}
		}
		mu.Unlock()

		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, len(data)))
		w.WriteHeader(http.StatusPartialContent)
		_, _ = w.Write(data[start : end+1])
	}))
	defer server.Close()

	outputPath := filepath.Join(t.TempDir(), "video.mp4")
	if err := downloadFile(server.URL, outputPath); err == nil {
		t.Fatal("expected first download attempt to fail")
	}
	if err := downloadFile(server.URL, outputPath); err != nil {
		t.Fatalf("resumed download failed: %v", err)
	}

	got, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("failed to read downloaded output: %v", err)
	}
	if !bytes.Equal(got, data) {
		t.Fatalf("downloaded output differs: got %d bytes, want %d", len(got), len(data))
	}
	if firstChunkRequests != 1 {
		t.Errorf("first chunk requested %d times, want once", firstChunkRequests)
	}
	if secondChunkRequests != downloadChunkMaxAttempts+1 {
		t.Errorf("second chunk requested %d times, want %d", secondChunkRequests, downloadChunkMaxAttempts+1)
	}

	if _, err := os.Stat(outputPath + ".parts"); !os.IsNotExist(err) {
		t.Errorf("download state should be removed after completion, stat error: %v", err)
	}
}
