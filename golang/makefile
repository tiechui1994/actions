UTIL=
LDFLAGS=

upload:clean verify
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

workflow:clean verify
	go build $(LDFLAGS) -o workflow workflow.go $(UTIL)

email:clean verify
	go build $(LDFLAGS) -o email email.go $(UTIL)

vedio:clean verify
	go build $(LDFLAGS) -o vedio vedio.go $(UTIL)

youtube:clean verify
	go build $(LDFLAGS) -o youtube youtube.go $(UTIL)

free:clean verify
	go build $(LDFLAGS) -o free free.go $(UTIL)

verify:
	go mod tidy

clean:
	rm -rf upload workflow sign email vedio youtube free
