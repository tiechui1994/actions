UTIL=util.go
LDFLAGS=-mod=mod

upload:clear
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

clean:clear
	go build $(LDFLAGS) -o clean clean.go $(UTIL)

sign:clear
	go build $(LDFLAGS) -o sign sign.go $(UTIL)

clear:
	rm -rf upload clean sign mail