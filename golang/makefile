LDFLAGS=-gcflags=all=-l -ldflags='-w -s'

upload:clean verify
	go build $(LDFLAGS) -o upload ./cmd/upload 

workflow:clean verify
	go build $(LDFLAGS) -o workflow ./cmd/workflow 

video:clean verify
	go build $(LDFLAGS) -o video ./cmd/video

verify:
	go mod tidy

clean:
	rm -rf upload workflow video
