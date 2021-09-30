package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/tiechui1994/tool/util"
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

	list, err := Runs(*r, 1, 100, *t)
	if err != nil {
		fmt.Println("fetch jobs error:", err)
		return
	}

	const (
		EVENTSCHEDULE = "schedule"
	)

	schedule := time.Now().Add(-3 * 24 * time.Hour)
	common := time.Now().Add(-7 * 24 * time.Hour)

	for _, v := range list {
		if v.Event == EVENTSCHEDULE && v.CreatedAt.Before(schedule) ||
			v.CreatedAt.Before(common) {
			err = DeleteRun(*r, v.ID, *t)
			fmt.Println("detail:", v.CreatedAt.Format("2006-01-02T15:04:05Z"), v.Name, v.Event, err)
		}
	}
}

// ============================================ API ============================================

const (
	github = "https://api.github.com"
)

type RunInfo struct {
	ID         int       `json:"id"`
	Name       string    `json:"name"`
	HeadBranch string    `json:"head_branch"`
	RunNumber  int       `json:"run_number"`
	Event      string    `json:"event"`
	Status     string    `json:"status"`
	WorkflowID int       `json:"workflow_id"`
	CreatedAt  time.Time `json:"created_at"`
}

func Runs(repo string, page, pagesize int, token string) (list []RunInfo, err error) {
	values := []string{
		"per_page=" + strconv.Itoa(pagesize),
		"page=" + strconv.Itoa(page),
	}
	u := github + "/repos/" + repo + "/actions/runs?" + strings.Join(values, "&")
	header := map[string]string{
		"accept":        "application/vnd.github.v3+json",
		"authorization": "token " + token,
	}

	raw, err := util.GET(u, header)
	if err != nil {
		return list, err
	}

	var result struct {
		Count int       `json:"total_count"`
		Runs  []RunInfo `json:"workflow_runs"`
	}
	err = json.Unmarshal(raw, &result)
	if err != nil {
		return list, err
	}

	list = result.Runs

	if len(result.Runs) == pagesize {
		next, err := Runs(repo, page+1, pagesize, token)
		if len(next) != 0 {
			list = append(list, next...)
		}
		if err != nil {
			return list, err
		}
	}

	return list, err
}

func DeleteRun(repo string, runid int, token string) error {
	u := github + "/repos/" + repo + "/actions/runs/" + strconv.Itoa(runid)
	header := map[string]string{
		"accept":        "application/vnd.github.v3+json",
		"authorization": "token " + token,
	}

	_, err := util.DELETE(u, header)
	return err
}
