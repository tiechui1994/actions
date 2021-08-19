UTIL=util.go
LDFLAGS=-mod=readonly

upload:clean
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

workflow:clean
	go build $(LDFLAGS) -o workflow workflow.go $(UTIL)

sign:clean
	go build $(LDFLAGS) -o sign sign.go $(UTIL)

email:clean
	go build $(LDFLAGS) -o email email.go $(UTIL)

clean:
	rm -rf upload workflow sign email