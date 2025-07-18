LDFLAGS=

upload:clean verify
	go build $(LDFLAGS) -o upload ./cmd/upload 

workflow:clean verify
	go build $(LDFLAGS) -o workflow ./cmd/workflow 

video:clean verify
	go build $(LDFLAGS) -o video ./cmd/video

youtube:clean verify
	go build $(LDFLAGS) -o youtube ./cmd/youtube 

tool:clean verify
	go build $(LDFLAGS) -o tool ./cmd/tool

streamlit:clean verify
	go build $(LDFLAGS) -o streamlit ./cmd/streamlit

verify:
	go mod tidy

clean:
	rm -rf upload workflow sign email video youtube free tool streamlit
