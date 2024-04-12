package utils

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/url"
	"strconv"
	"strings"

	"github.com/tiechui1994/tool/util"
	"gopkg.in/yaml.v3"
)

func Convert(file string, adapter bool) error {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		return err
	}

	var yamlStu struct {
		Proxy      []map[string]interface{} `yaml:"proxies"`
		ProxyGroup yaml.Node                `yaml:"proxy-groups"`
	}
	err = yaml.Unmarshal(data, &yamlStu)
	if err == nil {
		return nil
	}

	list, err := handleBase64(string(data))
	if adapter && err == nil && len(list) > 0 {
		ipList := make([]string, 0)
		for _, v := range list {
			if ip, ok := v["server"]; ok {
				ipList = append(ipList, ip.(string))
			}
		}

		raw, err := util.POST("https://quinn.deno.dev/api/ip", util.WithRetry(2),
			util.WithBody(strings.Join(ipList, "\n")))
		if err != nil {
			return fmt.Errorf("ip List: %w", err)
		}
		var stu []struct {
			IP     string `json:"ip"`
			Region string `json:"region"`
		}
		err = json.Unmarshal(raw, &stu)
		if err != nil {
			return fmt.Errorf("ip Unmarshal: %w", err)
		}

		ipListUnique := make(map[string]string)
		uniqueRegion := make(map[string]int)
		for _, v := range stu {
			ipListUnique[v.IP] = v.Region
			uniqueRegion[v.Region] += 1
		}

		for _, v := range list {
			if vv, ok := v["server"]; ok {
				ip := vv.(string)
				if region, ok := ipListUnique[ip]; ok {
					if uniqueRegion[region] == 1 {
						v["name"] = fmt.Sprintf("%v", region)
					} else {
						v["name"] = fmt.Sprintf("%v_%v", region, uniqueRegion[region])
						uniqueRegion[region] -= 1
					}
				} else {
					if uniqueRegion["free"] == 0 {
						v["name"] = "free"
						uniqueRegion["free"] += 1
					} else {
						v["name"] = fmt.Sprintf("free_%v", uniqueRegion["free"])
						uniqueRegion["free"] += 1
					}
				}
			}
		}

		yamlStu.Proxy = list
		raw, _ = yaml.Marshal(yamlStu)
		return ioutil.WriteFile(file, raw, 0666)
	}

	return fmt.Errorf("invalid type")
}

func handleBase64(base64Str string) ([]map[string]interface{}, error) {
	raw, err := base64.StdEncoding.DecodeString(base64Str)
	if err != nil {
		return nil, err
	}

	var all []map[string]interface{}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	for _, line := range lines {
		u, err := url.Parse(line)
		if err != nil {
			continue
		}

		var result map[string]interface{}
		switch u.Scheme {
		case "ss":
			result, err = handleSS(u)
		case "vmess":
			result, err = handleVmess(u)
		case "trojan":
			result, err = handleTrojan(u)
		case "vless":
			result, err = handleVless(u)
		}
		if err != nil || result == nil {
			fmt.Println("err:", err, u.String())
			continue
		}

		all = append(all, result)
	}

	return all, nil
}

func handleVless(u *url.URL) (map[string]interface{}, error) {
	query := u.Query()
	port, _ := strconv.Atoi(u.Port())
	vless := map[string]interface{}{
		"uuid":   u.User.Username(),
		"server": u.Hostname(),
		"port":   port,
		"type":   "vless",
	}

	switch query.Get("type") {
	case "ws":
		vless["network"] = "ws"
		wsOpt := make(map[string]interface{})
		if query.Has("path") {
			wsOpt["path"] = query.Get("path")
		}
		if query.Has("host") {
			wsOpt["headers"] = map[string]string{
				"Host": query.Get("host"),
			}
		}
		vless["ws-opts"] = wsOpt

	case "grpc":
		vless["network"] = "grpc"
		if query.Has("serviceName") {
			vless["grpc-opts"] = map[string]interface{}{
				"grpc-service-name": query.Get("serviceName"),
			}
		}
	}

	if query.Get("security") == "tls" {
		vless["tls"] = true
	}
	if query.Has("sni") {
		vless["servername"] = query.Get("sni")
	}
	if query.Get("allowInsecure") == "1" {
		vless["skip-cert-verify"] = true
	}

	return vless, nil
}

func handleTrojan(u *url.URL) (map[string]interface{}, error) {
	query := u.Query()
	port, _ := strconv.Atoi(u.Port())
	trojan := map[string]interface{}{
		"server":   u.Hostname(),
		"port":     port,
		"type":     "trojan",
		"password": u.User.String(),
	}

	switch query.Get("type") {
	case "ws":
		trojan["network"] = "ws"
		wsOpt := make(map[string]interface{})
		if query.Has("path") {
			wsOpt["path"] = query.Get("path")
		}
		if query.Has("host") {
			wsOpt["headers"] = map[string]string{
				"Host": query.Get("host"),
			}
		}
		trojan["ws-opts"] = wsOpt

	case "grpc":
		trojan["network"] = "grpc"
		if query.Has("serviceName") {
			trojan["grpc-opts"] = map[string]interface{}{
				"grpc-service-name": query.Get("serviceName"),
			}
		}
	}

	if query.Get("allowInsecure") == "1" {
		trojan["skip-cert-verify"] = true
	}
	if query.Has("sni") {
		trojan["sni"] = query.Get("sni")
	}
	if query.Has("alpn") {
		trojan["alpn"] = []string{query.Get("alpn")}
	}

	return trojan, nil
}

func handleSS(u *url.URL) (map[string]interface{}, error) {
	raw, err := base64.URLEncoding.DecodeString(u.User.String())
	if err != nil {
		return nil, err
	}

	port, _ := strconv.Atoi(u.Port())
	tokens := strings.Split(string(raw), ":")
	return map[string]interface{}{
		"server":   u.Hostname(),
		"port":     port,
		"type":     "ss",
		"cipher":   tokens[0],
		"password": tokens[1],
	}, nil
}

func handleVmess(u *url.URL) (map[string]interface{}, error) {
	raw, err := base64.StdEncoding.DecodeString(u.String()[len("vmess://"):])
	if err != nil {
		return nil, err
	}

	var result = make(map[string]interface{})
	err = json.Unmarshal(raw, &result)
	if err != nil {
		return nil, err
	}

	vmess := map[string]interface{}{
		"server":  result["add"],
		"port":    result["port"],
		"type":    "vmess",
		"uuid":    result["id"],
		"alterId": result["aid"],
		"network": result["net"],
		"cipher":  result["scy"],
	}

	if _, ok := result["skip-cert-verify"]; ok {
		vmess["skip-cert-verify"] = result["skip-cert-verify"]
	}

	switch vmess["network"] {
	case "ws":
		var wsOpts = make(map[string]interface{})
		if result["path"] != nil {
			wsOpts["path"] = result["path"]
		}
		if result["host"] != nil {
			wsOpts["headers"] = map[string]interface{}{
				"host": result["host"],
			}
		}
		vmess["ws-opts"] = wsOpts
	}

	return vmess, nil
}
