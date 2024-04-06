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
	repo := flag.String("repo", "", "github repo, eg: octocat/hello-world")
	token := flag.String("token", "", "github token")
	branch := flag.String("branch", "master", "github workflow branch")
	workflow := flag.String("workflow", "", "github workflow name")
	params := flag.String("param", `{}`, "github workflow exec params")
	flag.Parse()
	if *token == "" {
		fmt.Println("invalid github token")
		os.Exit(1)
	}
	if *repo == "" {
		fmt.Println("invalid github repo")
		os.Exit(1)
	}

	if *workflow == "" {
		list, err := RunList(*repo, 1, 100, *token)
		if err != nil {
			fmt.Println("fetch jobs error:", err)
			os.Exit(1)
		}

		schedule := time.Now().Add(-1 * 24 * time.Hour)
		common := time.Now().Add(-3 * 24 * time.Hour)
		for _, v := range list {
			if v.Event == "schedule" && v.CreatedAt.Before(schedule) ||
				v.CreatedAt.Before(common) {
				err = DeleteRun(*repo, v.ID, *token)
				fmt.Println("detail:", v.CreatedAt.Format("2006-01-02T15:04:05Z"), v.Name, v.Event, err)
			}
		}
	} else {
		var param = make(map[string]interface{})
		err := json.Unmarshal([]byte(*params), &param)
		if err != nil {
			fmt.Println("workflow params decode:", err)
			os.Exit(1)
		}

		err = RunWorkflow(*repo, *workflow, *branch, param, *token)
		if err != nil {
			fmt.Println("workflow:", *workflow, "run failed:", err)
			os.Exit(1)
		}

		fmt.Println("workflow:", *workflow, "run success")
	}
}

// ============================================ API ============================================

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

func RunList(repo string, page, pagesize int, token string) (list []RunInfo, err error) {
	values := []string{
		"per_page=" + strconv.Itoa(pagesize),
		"page=" + strconv.Itoa(page),
	}
	u := "https://api.github.com/repos/" + repo + "/actions/runs?" + strings.Join(values, "&")
	header := map[string]string{
		"accept":        "application/vnd.github.v3+json",
		"authorization": "token " + token,
	}

	raw, err := util.GET(u, util.WithHeader(header))
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
		next, err := RunList(repo, page+1, pagesize, token)
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
	u := "https://api.github.com/repos/" + repo + "/actions/runs/" + strconv.Itoa(runid)
	header := map[string]string{
		"accept":        "application/vnd.github.v3+json",
		"authorization": "token " + token,
	}

	_, err := util.DELETE(u, util.WithHeader(header))
	return err
}

func RunWorkflow(repo string, workflow, ref string, params map[string]interface{}, token string) error {
	u := "https://api.github.com/repos/" + repo + "/actions/workflows"
	header := map[string]string{
		"authorization": "Bearer " + token,
		"accept":        "application/vnd.github+json",
	}
	raw, err := util.GET(u, util.WithHeader(header))
	if err != nil {
		return fmt.Errorf("workflows get: %w", err)
	}

	var result struct {
		Workflows []struct {
			ID    int    `json:"id"`
			Name  string `json:"name"`
			Path  string `json:"path"`
			State string `json:"state"`
		} `json:"workflows"`
	}
	err = json.Unmarshal(raw, &result)
	if err != nil {
		return fmt.Errorf("workflow decode: %w", err)
	}

	var flowID string
	for _, flow := range result.Workflows {
		fmt.Println("flow => ", flow.Name, flow.Path)
		if (flow.Name == workflow || strings.HasSuffix(flow.Path, workflow+".yml")) && flow.State == "active" {
			flowID = fmt.Sprintf("%v", flow.ID)
			goto run
		}
	}
	return fmt.Errorf("no exist workflow")

run:
	u = "https://api.github.com/repos/" + repo + "/actions/workflows/" + flowID + "/dispatches"
	body := map[string]interface{}{
		"ref":    ref,
		"inputs": params,
	}
	_, err = util.POST(u, util.WithBody(body), util.WithHeader(header))
	if err != nil {
		return fmt.Errorf("workflow run: %w", err)
	}

	return nil
}
