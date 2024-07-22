package utils

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/url"
	"strconv"
	"strings"

	"github.com/tiechui1994/tool/util"
	"gopkg.in/yaml.v3"
)

type node = map[string]interface{}

func CombineToOneYaml(files []string, convert bool) ([]map[string]interface{}, error) {
	var list []node
	var uniqueEndpoint = make(map[string]bool)

	for _, file := range files {
		fileNodeList, err := getFileProxyList(file, convert)
		if err != nil {
			log.Printf("file=%v get failed: %v", file, err)
			continue
		}

		for _, node := range fileNodeList {
			key := fmt.Sprintf("%v_%v_%v", node["type"], node["server"], node["port"])
			if uniqueEndpoint[key] {
				continue
			}

			uniqueEndpoint[key] = true
			list = append(list, node)
		}
	}

	return list, nil
}

func getFileProxyList(file string, convert bool) ([]node, error) {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	var yamlStu struct {
		Proxy []node `yaml:"proxies"`
	}

	type region struct {
		IP     string `json:"ip"`
		Region string `json:"region"`
	}
	setRegion := func() ([]region, error) {
		ipList := make([]string, 0)
		for _, v := range yamlStu.Proxy {
			if ip, ok := v["server"]; ok {
				ipList = append(ipList, ip.(string))
			}
		}
		raw, err := util.POST("https://quinn.deno.dev/api/ip", util.WithRetry(2),
			util.WithBody(strings.Join(ipList, "\n")))
		if err != nil {
			return nil, fmt.Errorf("ip List: %w", err)
		}
		var stu []region
		err = json.Unmarshal(raw, &stu)
		if err != nil {
			return nil, fmt.Errorf("ip Unmarshal: %w", err)
		}
		var serverRegion = make(map[string]string)
		for _, v := range stu {
			serverRegion[v.IP] = v.Region
		}
		for _, v := range yamlStu.Proxy {
			if ip, ok := v["server"]; ok {
				v["region"] = serverRegion[ip.(string)]
			}
		}

		return stu, nil
	}

	err = yaml.Unmarshal(data, &yamlStu)
	if err == nil {
		_, _ = setRegion()
		return yamlStu.Proxy, nil
	}

	if !convert {
		goto handle
	}

	// 转换失败, 尝试 base64
	yamlStu.Proxy, err = handleBase64(string(data))
	if err == nil && len(yamlStu.Proxy) > 0 {
		stu, err := setRegion()
		if err != nil {
			return nil, err
		}

		// name ready
		ipListUnique := make(map[string]string)
		uniqueRegion := make(map[string]int)
		for _, v := range stu {
			ipListUnique[v.IP] = v.Region
			uniqueRegion[v.Region] += 1
		}

		// set name
		invalidIndex := make(map[int]bool, 0)
		for index, v := range yamlStu.Proxy {
			server, ok := v["server"]
			if !ok {
				invalidIndex[index] = true
				continue
			}

			ip := server.(string)
			if region, ok := ipListUnique[ip]; ok {
				if region == "0" {
					invalidIndex[index] = true
					continue
				}
				if uniqueRegion[region] == 1 {
					v["name"] = fmt.Sprintf("%v", region)
				} else {
					v["name"] = fmt.Sprintf("%v_%v", region, uniqueRegion[region])
					uniqueRegion[region] -= 1
				}
			} else {
				idx := strings.Index(ip, ".")
				if idx == -1 {
					if len(ip) > 3 {
						idx = 3
					} else {
						idx = len(ip)
					}
				}
				name := fmt.Sprintf("节点_%v", ip[:idx])
				if uniqueRegion[name] == 0 {
					v["name"] = name
					uniqueRegion[name] += 1
				} else {
					v["name"] = fmt.Sprintf("%v%v", name, uniqueRegion[name])
					uniqueRegion[name] += 1
				}
			}
		}

		// remove invalid endpoint
		if len(invalidIndex) > 0 {
			newList := make([]map[string]interface{}, 0)
			for i, v := range yamlStu.Proxy {
				if invalidIndex[i] {
					continue
				}
				newList = append(newList, v)
			}
			yamlStu.Proxy = newList
		}

		return yamlStu.Proxy, nil
	}

handle:
	// 其他
	return nil, fmt.Errorf("invalid type: %w", err)
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
