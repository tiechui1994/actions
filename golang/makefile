UTIL=
LDFLAGS=

upload:clean verify
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

workflow:clean verify
	go build $(LDFLAGS) -o workflow workflow.go $(UTIL)

video:clean verify
	go build $(LDFLAGS) -o video video.go $(UTIL)

youtube:clean verify
	go build $(LDFLAGS) -o youtube youtube.go $(UTIL)

verify:
	go mod tidy -compat=1.17

clean:
	rm -rf upload workflow sign email video youtube free
