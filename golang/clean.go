package main

import (
	"flag"
	"fmt"
	"os"
	"time"
)

func main() {
	r := flag.String("r", "", "github repo, eg: octocat/hello-world ")
	t := flag.String("t", "", "github token")
	flag.Parse()
	if *t == "" {
		fmt.Println("invalid github token")
		os.Exit(1)
	}
	if *r == "" {
		fmt.Println("invalid github repo")
		os.Exit(1)
	}

	after := time.Now().Add(-7 * 24 * time.Hour)
	list, err := Runs(*r, 1, 100, *t)
	if err != nil {
		fmt.Println("fetch jobs error:", err)
		return
	}

	for _, v := range list {
		if v.CreatedAt.Before(after) {
			err = DeleteRun(*r, v.ID, *t)
			fmt.Println("detail:", v.CreatedAt.Format("2006-01-02T15:04:05Z"), v.Name, v.Event, err)
		}
	}
}
