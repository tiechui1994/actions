UTIL=util.go

upload:clear
	go build -o upload upload.go $(UTIL)

clean:clear
	go build -o clean clean.go $(UTIL)

sign:clear
	go build -o sign sign.go $(UTIL)

clear:
	rm -rf upload clean sign