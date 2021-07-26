package main

import (
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

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

	raw, err := GET(u, header)
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

	_, err := DELETE(u, header)
	return err
}
