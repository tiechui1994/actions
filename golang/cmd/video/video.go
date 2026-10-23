package main

import (
	"bytes"
	"crypto/md5"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/tiechui1994/tool/log"
	"github.com/tiechui1994/tool/util"
)

func logRequest(request *http.Request) {
	log.Infoln("%v - %v", request.Method, request.RequestURI)
}

var showDownloadProgress = true

func configureDownloadProgress(enabled bool) {
	showDownloadProgress = enabled
}

func main() {
	name := flag.String("name", "", "output file path")
	url := flag.String("url", "", "video url (YouTube or m3u8 streaming url)")
	batch := flag.Int("batch", 10, "parallel count for m3u8 streams")
	quality := flag.String("quality", "1080p,720p,best", "preferred quality for YouTube (1080p/720p/360p/240p/best)")
	proxy := flag.String("proxy", "", "HTTP/HTTPS proxy URL (e.g. http://127.0.0.1:7890)")
	progress := flag.Bool("progress", true, "show download progress during file transfers")
	flag.Parse()
	configureDownloadProgress(*progress)
	if err := configureVideoProxy(*proxy); err != nil {
		fmt.Println("Invalid proxy:", err)
		os.Exit(1)
	}

	if *url == "" || !strings.HasPrefix(*url, "http") {
		fmt.Println("invalid url")
		os.Exit(1)
	}
	if *name == "" {
		fmt.Println("invalid name")
		os.Exit(1)
	}

	fmt.Println("filepath:", *name)

	if isYouTubeURL(*url) {
		fmt.Println("Detected YouTube URL, using iiilab API to extract...")
		if err := downloadYouTubeViaAPI(*url, *name, *quality); err != nil {
			fmt.Println("YouTube Download Failed:", err)
			os.Exit(1)
		}
		fmt.Println("download success!!!")
		return
	}

	fd, err := os.Create(*name)
	if err != nil {
		fmt.Println("Create File:", err)
		os.Exit(1)
	}
	defer fd.Close()

	if err = Download(*url, *batch, fd); err != nil {
		fmt.Println("Download Failed:", err)
		os.Exit(1)
	}

	fmt.Println("download success!!!")
}

// ============================================ YOUTUBE FUNCTIONS ============================================

const (
	iiiLabAPIURL        = "https://webapi.iiilab.com/api/web/extract"
	iiiLabSignatureSalt = "JSnHKQfP1IlzIQzs"
)

var videoProxy func(*http.Request) (*url.URL, error)

func configureVideoProxy(proxyAddress string) error {
	proxyAddress = strings.TrimSpace(proxyAddress)
	if proxyAddress == "" {
		videoProxy = nil
		return nil
	}

	proxyURL, err := url.Parse(proxyAddress)
	if err != nil {
		return fmt.Errorf("invalid proxy URL: %w", err)
	}
	if (proxyURL.Scheme != "http" && proxyURL.Scheme != "https") || proxyURL.Host == "" {
		return fmt.Errorf("proxy must be an HTTP or HTTPS URL with a host")
	}
	fmt.Println("using proxy", proxyURL.String())
	videoProxy = http.ProxyURL(proxyURL)
	return nil
}

func newVideoHTTPClient(timeout time.Duration) *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if videoProxy != nil {
		transport.Proxy = videoProxy
	}
	return &http.Client{Timeout: timeout, Transport: transport}
}

func videoUtilGet(u string, options ...util.Option) (json.RawMessage, error) {
	if videoProxy != nil {
		options = append(options, util.WithProxy(videoProxy))
	}
	return util.GET(u, options...)
}

func iiiLabFooter(videoURL string, timestamp string) string {
	signature := videoURL + "youtube" + timestamp + iiiLabSignatureSalt
	return fmt.Sprintf("%x", md5.Sum([]byte(signature)))
}

// VideoQuality represents a video format with quality info
type VideoQuality struct {
	Quality  string
	Height   int
	URL      string
	AudioURL string
	MimeType string
	FileSize int64
}

// iiiLabResponse represents the API response structure.
type iiiLabResponse struct {
	Medias []struct {
		MediaType string         `json:"media_type"`
		Formats   []iiiLabFormat `json:"formats"`
		Variants  []iiiLabFormat `json:"variants"`
	} `json:"medias"`
	ID      string `json:"id"`
	PostURL string `json:"post_url"`
}

type iiiLabFormat struct {
	Quality       int    `json:"quality"`
	QualityLabel  string `json:"quality_label"`
	VideoURL      string `json:"video_url"`
	AudioURL      string `json:"audio_url"`
	VideoExt      string `json:"video_ext"`
	VideoFileSize int64  `json:"video_filesize"`
}

func isYouTubeURL(u string) bool {
	return strings.Contains(u, "youtube.com") || strings.Contains(u, "youtu.be")
}

// extractVideoFormatsFromAPI calls iiilab API to get video formats
func extractVideoFormatsFromAPI(videoURL string) ([]VideoQuality, error) {
	return extractVideoFormatsFromAPIWithClient(videoURL, iiiLabAPIURL)
}

func extractVideoFormatsFromAPIWithClient(videoURL string, apiURL string) ([]VideoQuality, error) {
	payload := map[string]string{
		"url":  videoURL,
		"site": "youtube",
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("content-type", "application/json")
	req.Header.Set("origin", "https://youtube.iiilab.com")
	req.Header.Set("referer", "https://youtube.iiilab.com/")
	req.Header.Set("user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36")
	timestamp := strconv.FormatInt(time.Now().UnixMilli()/1000, 10)
	req.Header.Set("G-Timestamp", timestamp)
	req.Header.Set("G-Footer", iiiLabFooter(videoURL, timestamp))

	fmt.Println("Calling iiilab API to extract video formats...")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("API request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var apiResp iiiLabResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil, fmt.Errorf("failed to decode API response: %w", err)
	}

	fmt.Printf("Video ID: %s\n", apiResp.ID)

	var qualities []VideoQuality
	for _, media := range apiResp.Medias {
		if media.MediaType != "video" {
			continue
		}

		formats := media.Formats
		if len(formats) == 0 {
			formats = media.Variants
		}
		for _, format := range formats {
			quality := format.QualityLabel
			if quality == "" && format.Quality > 0 {
				quality = fmt.Sprintf("%dp", format.Quality)
			}
			mimeType := ""
			if format.VideoExt != "" {
				mimeType = "video/" + format.VideoExt
			}

			qualities = append(qualities, VideoQuality{
				Quality:  quality,
				Height:   format.Quality,
				URL:      format.VideoURL,
				AudioURL: format.AudioURL,
				MimeType: mimeType,
				FileSize: format.VideoFileSize,
			})
		}
	}
	fmt.Printf("Found %d formats\n", len(qualities))

	return qualities, nil
}

// selectQualityURL selects the best matching quality from available formats
func selectQualityURL(availableQualities []VideoQuality, preferredQualities []string) (VideoQuality, error) {
	if len(availableQualities) == 0 {
		return VideoQuality{}, fmt.Errorf("no video formats available")
	}

	for _, pref := range preferredQualities {
		pref = strings.TrimSpace(pref)
		if pref == "best" {
			var best VideoQuality
			maxHeight := 0
			for _, q := range availableQualities {
				if q.Height > maxHeight {
					maxHeight = q.Height
					best = q
				}
			}
			if maxHeight > 0 {
				fmt.Printf("Selected quality: %s (%dp, %s, %d bytes)\n", best.Quality, best.Height, best.MimeType, best.FileSize)
				return best, nil
			}
			continue
		}

		heightStr := strings.TrimSuffix(pref, "p")
		heightStr = strings.TrimSuffix(heightStr, "P")
		preferredHeight, err := strconv.Atoi(heightStr)
		if err != nil {
			continue
		}

		for _, q := range availableQualities {
			if q.Height == preferredHeight {
				fmt.Printf("Selected quality: %s (%dp, %s, %d bytes)\n", q.Quality, q.Height, q.MimeType, q.FileSize)
				return q, nil
			}
		}
	}

	var best VideoQuality
	maxHeight := 0
	for _, q := range availableQualities {
		if q.Height > maxHeight {
			maxHeight = q.Height
			best = q
		}
	}

	if maxHeight > 0 {
		fmt.Printf("Fallback: Selected quality: %s (%dp, %s, %d bytes)\n", best.Quality, best.Height, best.MimeType, best.FileSize)
		return best, nil
	}

	return availableQualities[0], nil
}

const (
	downloadChunkSize        = int64(8 * 1024 * 1024)
	downloadWorkers          = 3
	downloadChunkMaxAttempts = 6
)

type downloadProgress struct {
	mu             sync.Mutex
	total          int64
	completed      int64
	lastReportTime time.Time
	enabled        bool
}

func newDownloadProgress(total int64) *downloadProgress {
	progress := &downloadProgress{total: total, lastReportTime: time.Now(), enabled: showDownloadProgress}
	progress.report()
	return progress
}

func (p *downloadProgress) add(size int64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.completed += size
	if time.Since(p.lastReportTime) >= 300*time.Millisecond || (p.total > 0 && p.completed >= p.total) {
		p.reportLocked()
	}
}

func (p *downloadProgress) finish() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if !p.enabled {
		return
	}
	p.reportLocked()
	fmt.Println()
}

func (p *downloadProgress) report() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.reportLocked()
}

func (p *downloadProgress) reportLocked() {
	if !p.enabled {
		p.lastReportTime = time.Now()
		return
	}
	if p.total > 0 {
		percentage := float64(p.completed) / float64(p.total) * 100
		fmt.Printf("\rDownload progress: %.1f%% (%.2f/%.2f MB)", percentage, float64(p.completed)/(1024*1024), float64(p.total)/(1024*1024))
	} else {
		fmt.Printf("\rDownloaded: %.2f MB", float64(p.completed)/(1024*1024))
	}
	p.lastReportTime = time.Now()
	if p.total > 0 && p.completed >= p.total {
		fmt.Println()
	}
}

type progressReader struct {
	reader   io.Reader
	progress *downloadProgress
}

func (r progressReader) Read(buffer []byte) (int, error) {
	count, err := r.reader.Read(buffer)
	if count > 0 {
		r.progress.add(int64(count))
	}
	return count, err
}

type downloadState struct {
	URL       string `json:"url"`
	Size      int64  `json:"size"`
	ChunkSize int64  `json:"chunk_size"`
}

type downloadURLState struct {
	mu      sync.Mutex
	current string
	refresh func() (string, error)
}

func (s *downloadURLState) get() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.current
}

func (s *downloadURLState) refreshAfterFailure(failedURL string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.current != failedURL || s.refresh == nil {
		return s.current, nil
	}
	refreshedURL, err := s.refresh()
	if err != nil {
		return "", err
	}
	s.current = refreshedURL
	return s.current, nil
}

func newDownloadRequest(fileURL string) (*http.Request, error) {
	req, err := http.NewRequest("GET", fileURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create download request: %w", err)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Referer", "https://youtube.iiilab.com/")
	return req, nil
}

func downloadFile(fileURL string, outputPath string) error {
	return downloadFileWithRefresh(fileURL, outputPath, nil)
}

func downloadFileWithRefresh(fileURL string, outputPath string, refreshURL func() (string, error)) error {
	client := newVideoHTTPClient(5 * time.Minute)
	fmt.Printf("Downloading from: %s\n", fileURL)

	probeReq, err := newDownloadRequest(fileURL)
	if err != nil {
		return err
	}
	probeReq.Header.Set("Range", "bytes=0-0")
	probeResp, err := client.Do(probeReq)
	if err != nil {
		return fmt.Errorf("download request failed: %w", err)
	}
	if probeResp.StatusCode == http.StatusOK {
		defer probeResp.Body.Close()
		return saveDownloadResponse(probeResp.Body, outputPath, probeResp.ContentLength)
	}
	if probeResp.StatusCode != http.StatusPartialContent {
		defer probeResp.Body.Close()
		return fmt.Errorf("download probe failed with status %d", probeResp.StatusCode)
	}
	resolvedURL := fileURL
	if probeResp.Request != nil && probeResp.Request.URL != nil {
		resolvedURL = probeResp.Request.URL.String()
	}
	start, end, totalSize, err := parseContentRange(probeResp.Header.Get("Content-Range"))
	probeResp.Body.Close()
	if err != nil {
		return fmt.Errorf("invalid range response: %w", err)
	}
	if start != 0 || end != 0 {
		return fmt.Errorf("unexpected range probe response: bytes %d-%d", start, end)
	}
	if totalSize <= 0 {
		return fmt.Errorf("invalid download size: %d", totalSize)
	}

	return downloadFileInChunksWithRefresh(client, fileURL, resolvedURL, outputPath, totalSize, refreshURL)
}

func saveDownloadResponse(body io.Reader, outputPath string, totalSize int64) error {
	outputDir := filepath.Dir(outputPath)
	temp, err := os.CreateTemp(outputDir, ".download-*")
	if err != nil {
		return fmt.Errorf("failed to create temporary output file: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	progress := newDownloadProgress(totalSize)
	if _, err := io.Copy(temp, progressReader{reader: body, progress: progress}); err != nil {
		temp.Close()
		return fmt.Errorf("failed to write file: %w", err)
	}
	progress.finish()
	if err := temp.Close(); err != nil {
		return fmt.Errorf("failed to close output file: %w", err)
	}
	if err := os.Rename(tempPath, outputPath); err != nil {
		return fmt.Errorf("failed to save output file: %w", err)
	}
	return nil
}

func parseContentRange(value string) (int64, int64, int64, error) {
	var start, end, total int64
	if _, err := fmt.Sscanf(value, "bytes %d-%d/%d", &start, &end, &total); err != nil {
		return 0, 0, 0, err
	}
	if start < 0 || end < start || total <= end {
		return 0, 0, 0, fmt.Errorf("unexpected content range %q", value)
	}
	return start, end, total, nil
}

func downloadFileInChunks(client *http.Client, sourceURL string, downloadURL string, outputPath string, totalSize int64) error {
	return downloadFileInChunksWithRefresh(client, sourceURL, downloadURL, outputPath, totalSize, nil)
}

func downloadFileInChunksWithRefresh(client *http.Client, sourceURL string, downloadURL string, outputPath string, totalSize int64, refreshURL func() (string, error)) error {
	partsDir := outputPath + ".parts"
	statePath := filepath.Join(partsDir, "state.json")
	state := downloadState{URL: sourceURL, Size: totalSize, ChunkSize: downloadChunkSize}

	if err := os.MkdirAll(partsDir, 0755); err != nil {
		return fmt.Errorf("failed to create download state directory: %w", err)
	}
	stateData, err := os.ReadFile(statePath)
	if err == nil {
		var existing downloadState
		if json.Unmarshal(stateData, &existing) != nil || existing != state {
			if err := os.RemoveAll(partsDir); err != nil {
				return fmt.Errorf("failed to reset incompatible download state: %w", err)
			}
			if err := os.MkdirAll(partsDir, 0755); err != nil {
				return fmt.Errorf("failed to recreate download state directory: %w", err)
			}
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("failed to read download state: %w", err)
	}
	stateData, err = json.Marshal(state)
	if err != nil {
		return fmt.Errorf("failed to encode download state: %w", err)
	}
	if err := os.WriteFile(statePath, stateData, 0644); err != nil {
		return fmt.Errorf("failed to save download state: %w", err)
	}

	chunkCount := int((totalSize + downloadChunkSize - 1) / downloadChunkSize)
	jobs := make(chan int)
	var workers sync.WaitGroup
	var firstErr error
	var errOnce sync.Once
	progress := newDownloadProgress(totalSize)
	urlState := &downloadURLState{current: downloadURL, refresh: refreshURL}
	workerCount := downloadWorkers
	if chunkCount < workerCount {
		workerCount = chunkCount
	}

	for worker := 0; worker < workerCount; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for chunkIndex := range jobs {
				if err := downloadChunkWithRefresh(client, urlState, partsDir, chunkIndex, totalSize, func(size int64) {
					progress.add(size)
				}); err != nil {
					errOnce.Do(func() { firstErr = err })
				}
			}
		}()
	}
	for chunkIndex := 0; chunkIndex < chunkCount; chunkIndex++ {
		jobs <- chunkIndex
	}
	close(jobs)
	workers.Wait()
	if firstErr != nil {
		return firstErr
	}

	outputDir := filepath.Dir(outputPath)
	temp, err := os.CreateTemp(outputDir, ".download-*")
	if err != nil {
		return fmt.Errorf("failed to create temporary output file: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	for chunkIndex := 0; chunkIndex < chunkCount; chunkIndex++ {
		partPath := filepath.Join(partsDir, fmt.Sprintf("%08d.part", chunkIndex))
		part, err := os.Open(partPath)
		if err != nil {
			temp.Close()
			return fmt.Errorf("failed to open downloaded chunk: %w", err)
		}
		_, copyErr := io.Copy(temp, part)
		closeErr := part.Close()
		if copyErr != nil {
			temp.Close()
			return fmt.Errorf("failed to assemble downloaded chunks: %w", copyErr)
		}
		if closeErr != nil {
			temp.Close()
			return fmt.Errorf("failed to close downloaded chunk: %w", closeErr)
		}
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("failed to close output file: %w", err)
	}
	if err := os.Rename(tempPath, outputPath); err != nil {
		return fmt.Errorf("failed to save output file: %w", err)
	}
	if err := os.RemoveAll(partsDir); err != nil {
		return fmt.Errorf("download complete but failed to remove chunk files: %w", err)
	}
	return nil
}

func downloadChunk(client *http.Client, fileURL string, partsDir string, chunkIndex int, totalSize int64) error {
	return downloadChunkWithRefresh(client, &downloadURLState{current: fileURL}, partsDir, chunkIndex, totalSize, nil)
}

type downloadHTTPStatusError struct {
	statusCode int
}

func (e downloadHTTPStatusError) Error() string {
	return fmt.Sprintf("server returned status %d", e.statusCode)
}

func downloadChunkWithRefresh(client *http.Client, urlState *downloadURLState, partsDir string, chunkIndex int, totalSize int64, progress func(int64)) error {
	var lastErr error
	for attempt := 1; attempt <= downloadChunkMaxAttempts; attempt++ {
		currentFileURL := urlState.get()
		if err := downloadChunkAttempt(client, currentFileURL, partsDir, chunkIndex, totalSize); err == nil {
			chunkSize := downloadChunkSize
			if remaining := totalSize - int64(chunkIndex)*downloadChunkSize; remaining < chunkSize {
				chunkSize = remaining
			}
			if progress != nil {
				progress(chunkSize)
			}
			return nil
		} else {
			lastErr = err
			var statusErr downloadHTTPStatusError
			retryImmediately := false
			if errors.As(err, &statusErr) && statusErr.statusCode == http.StatusForbidden {
				refreshedURL, refreshErr := urlState.refreshAfterFailure(currentFileURL)
				if refreshErr != nil {
					return fmt.Errorf("failed to refresh URL for chunk %d after HTTP 403: %w", chunkIndex, refreshErr)
				}
				retryImmediately = refreshedURL != currentFileURL
			}
			if attempt < downloadChunkMaxAttempts && !retryImmediately {
				time.Sleep(time.Duration(attempt) * 200 * time.Millisecond)
			}
			continue
		}
	}
	return fmt.Errorf("failed to download chunk %d after %d attempts: %w", chunkIndex, downloadChunkMaxAttempts, lastErr)
}

func downloadChunkAttempt(client *http.Client, fileURL string, partsDir string, chunkIndex int, totalSize int64) error {
	start := int64(chunkIndex) * downloadChunkSize
	end := start + downloadChunkSize - 1
	if end >= totalSize {
		end = totalSize - 1
	}
	partPath := filepath.Join(partsDir, fmt.Sprintf("%08d.part", chunkIndex))
	if info, err := os.Stat(partPath); err == nil && info.Size() == end-start+1 {
		return nil
	}

	req, err := newDownloadRequest(fileURL)
	if err != nil {
		return err
	}
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", start, end))
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to download chunk %d: %w", chunkIndex, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		return fmt.Errorf("failed to download chunk %d: %w", chunkIndex, downloadHTTPStatusError{statusCode: resp.StatusCode})
	}
	actualStart, actualEnd, actualTotal, err := parseContentRange(resp.Header.Get("Content-Range"))
	if err != nil || actualStart != start || actualEnd != end || actualTotal != totalSize {
		return fmt.Errorf("failed to download chunk %d: unexpected Content-Range %q", chunkIndex, resp.Header.Get("Content-Range"))
	}

	temp, err := os.CreateTemp(partsDir, ".chunk-*")
	if err != nil {
		return fmt.Errorf("failed to create temporary chunk: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	copied, copyErr := io.Copy(temp, io.LimitReader(resp.Body, end-start+1))
	closeErr := temp.Close()
	if copyErr != nil {
		return fmt.Errorf("failed to write chunk %d: %w", chunkIndex, copyErr)
	}
	if closeErr != nil {
		return fmt.Errorf("failed to close chunk %d: %w", chunkIndex, closeErr)
	}
	if copied != end-start+1 {
		return fmt.Errorf("chunk %d was incomplete: received %d of %d bytes", chunkIndex, copied, end-start+1)
	}
	if err := os.Rename(tempPath, partPath); err != nil {
		return fmt.Errorf("failed to save chunk %d: %w", chunkIndex, err)
	}
	return nil
}

func downloadAndMergeVideo(videoURL string, audioURL string, outputPath string) error {
	return downloadAndMergeVideoWithRefresh(videoURL, audioURL, outputPath, nil, nil)
}

func downloadAndMergeVideoWithRefresh(videoURL string, audioURL string, outputPath string, refreshVideoURL func() (string, error), refreshAudioURL func() (string, error)) error {
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg is required to combine separate video and audio streams: %w", err)
	}

	outputDir := filepath.Dir(outputPath)
	tempDir, err := os.MkdirTemp(outputDir, ".video-download-*")
	if err != nil {
		return fmt.Errorf("failed to create temporary directory: %w", err)
	}
	defer os.RemoveAll(tempDir)

	videoPath := filepath.Join(tempDir, "video")
	audioPath := filepath.Join(tempDir, "audio")

	var wg sync.WaitGroup
	wg.Add(2)
	var videoErr, audioErr error
	go func() {
		defer wg.Done()
		videoErr = downloadFileWithRefresh(videoURL, videoPath, refreshVideoURL)
	}()
	go func() {
		defer wg.Done()
		audioErr = downloadFileWithRefresh(audioURL, audioPath, refreshAudioURL)
	}()
	wg.Wait()

	if videoErr != nil {
		return fmt.Errorf("failed to download video stream: %w", videoErr)
	}
	if audioErr != nil {
		return fmt.Errorf("failed to download audio stream: %w", audioErr)
	}

	outputTemp, err := os.CreateTemp(outputDir, ".video-merge-*"+filepath.Ext(outputPath))
	if err != nil {
		return fmt.Errorf("failed to create temporary output file: %w", err)
	}
	outputTempPath := outputTemp.Name()
	if err := outputTemp.Close(); err != nil {
		os.Remove(outputTempPath)
		return fmt.Errorf("failed to prepare temporary output file: %w", err)
	}
	defer os.Remove(outputTempPath)

	cmd := exec.Command(ffmpegPath,
		"-y",
		"-i", videoPath,
		"-i", audioPath,
		"-map", "0:v:0",
		"-map", "1:a:0",
		"-c", "copy",
		outputTempPath,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to merge video and audio with ffmpeg: %w: %s", err, strings.TrimSpace(string(output)))
	}

	if err := os.Rename(outputTempPath, outputPath); err != nil {
		return fmt.Errorf("failed to save merged video: %w", err)
	}
	return nil
}

// downloadYouTubeViaAPI downloads YouTube video via iiilab API
func downloadYouTubeViaAPI(videoURL string, outputPath string, qualityStr string) error {
	outputDir := filepath.Dir(outputPath)
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("failed to create output directory: %w", err)
	}

	qualities, err := extractVideoFormatsFromAPI(videoURL)
	if err != nil {
		return err
	}

	preferredQualities := strings.Split(qualityStr, ",")
	selected, err := selectQualityURL(qualities, preferredQualities)
	if err != nil {
		return err
	}

	fmt.Printf("MIME type: %s\n", selected.MimeType)
	refreshSelectedURL := func(audio bool) func() (string, error) {
		return func() (string, error) {
			refreshedQualities, err := extractVideoFormatsFromAPI(videoURL)
			if err != nil {
				return "", err
			}
			refreshed, err := selectQualityURL(refreshedQualities, preferredQualities)
			if err != nil {
				return "", err
			}
			if audio {
				if refreshed.AudioURL == "" {
					return "", fmt.Errorf("refreshed format has no audio URL")
				}
				return refreshed.AudioURL, nil
			}
			return refreshed.URL, nil
		}
	}

	_, name := filepath.Split(outputPath)
	if ext := filepath.Ext(name); ext == "mp3" || ext == "wav" || ext == "m4a" || ext == "aac" || ext == "ogg" {
		selected.URL = ""
	}

	if selected.AudioURL != "" && selected.URL != "" {
		if err := downloadAndMergeVideoWithRefresh(selected.URL, selected.AudioURL, outputPath, refreshSelectedURL(false), refreshSelectedURL(true)); err != nil {
			return err
		}
	} else if selected.AudioURL != "" {
		if err := downloadFileWithRefresh(selected.AudioURL, outputPath, refreshSelectedURL(true)); err != nil {
			return err
		}
	} else {
		if err := downloadFileWithRefresh(selected.URL, outputPath, refreshSelectedURL(false)); err != nil {
			return err
		}
	}

	fileInfo, err := os.Stat(outputPath)
	if err != nil {
		return fmt.Errorf("output file verification failed: %w", err)
	}

	fmt.Printf("Download complete! File size: %.2f MB\n", float64(fileInfo.Size())/(1024*1024))
	return nil
}

// ============================================ M3U8 STREAMING FUNCTIONS ============================================

const (
	EXTM3U         = "#EXTM3U"
	VERSION        = "#EXT-X-VERSION"
	SEQUENCE       = "#EXT-X-MEDIA-SEQUENCE"
	CACHE          = "#EXT-X-ALLOW-CACHE"
	KEY            = "#EXT-X-KEY"
	TARGETDURATION = "#EXT-X-TARGETDURATION"
	EXTINF         = "#EXTINF"
	EXTSTREAMINF   = "#EXT-X-STREAM-INF"
	ENDLIST        = "#EXT-X-ENDLIST"
)

// https://cctvalih5ca.v.myalicdn.com/live/cctv2_2/index.m3u8
func Download(u string, batch int, fd io.Writer) error {
	lastIndex := strings.LastIndex(u, "/")
	endpoint := u[:lastIndex]
	raw, err := videoUtilGet(u, util.WithRetry(4), util.WithBeforeRequest(logRequest))
	if err != nil {
		fmt.Println("url:", u, "err:", err)
		return err
	}

	tokens := strings.Split(string(raw), "\n")
	urls := make([]string, 0, 100)
	for idx := 0; idx < len(tokens); idx += 1 {
		token := strings.TrimSpace(tokens[idx])
		if len(token) == 0 {
			continue
		}

		if strings.HasPrefix(token, EXTINF) {
			u := strings.TrimSpace(tokens[idx+1])
			if strings.HasPrefix(u, "http") {
				urls = append(urls, u)
				idx += 1
			} else if strings.HasPrefix(u, "/") {
				urls = append(urls, endpoint+u)
				idx += 1
			} else {
				urls = append(urls, endpoint+"/"+u)
				idx += 1
			}
		} else if strings.HasPrefix(token, EXTSTREAMINF) {
			u := strings.TrimSpace(tokens[idx+1])
			if strings.HasPrefix(u, "http") {
				idx += 1
			} else if strings.HasPrefix(u, "/") {
				u = endpoint + u
				idx += 1
			} else {
				u = endpoint + "/" + u
				idx += 1
			}

			return Download(u, batch, fd)
		}
	}

	download := func(u string) (data []byte, err error) {
		raw, err := videoUtilGet(u, util.WithRetry(3), util.WithBeforeRequest(logRequest))
		if err != nil {
			fmt.Println("url:", u, "err:", err)
			return data, err
		}

		return raw, nil
	}

	var wg sync.WaitGroup
	step := batch
	for i := 0; i < len(urls); i += step {
		count := step
		if i+step >= len(urls) {
			count = len(urls) - i
		}

		data := make([][]byte, count)
		failed := false
		for k := 0; k < count; k++ {
			wg.Add(1)
			idx := k
			go func(idx int) {
				defer wg.Done()
				raw, err := download(urls[i+idx])
				if err != nil {
					failed = true
					return
				}
				data[idx] = raw
			}(idx)
		}
		wg.Wait()

		if failed {
			fmt.Println("download failed")
			os.Exit(1)
		}

		for i := range data {
			_, _ = fd.Write(data[i])
		}
	}

	return nil
}
