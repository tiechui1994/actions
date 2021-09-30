UTIL=
LDFLAGS=-mod=readonly

upload:clean verify
	go build $(LDFLAGS) -o upload upload.go $(UTIL)

workflow:clean verify
	go build $(LDFLAGS) -o workflow workflow.go $(UTIL)

sign:clean verify
	go build $(LDFLAGS) -o sign sign.go $(UTIL)

email:clean verify
	go build $(LDFLAGS) -o email email.go $(UTIL)

verify:
	go mod verify
	go mod tidy

clean:
	rm -rf upload workflow sign email