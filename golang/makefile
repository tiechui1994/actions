UTIL=util.go
LDFLAGS=-mod=readonly

upload:clear
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

clean:clear
	go build $(LDFLAGS) -o clean clean.go $(UTIL)

sign:clear
	go build $(LDFLAGS) -o sign sign.go $(UTIL)

mail:clear
	go build $(LDFLAGS) -o mail mail.go $(UTIL)

clear:
	rm -rf upload clean sign mail