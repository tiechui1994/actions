package main

import (
	"gopkg.in/yaml.v3"
	"io/ioutil"
	"os"
	"testing"
)

func TestRawConfig(t *testing.T) {
	raw, err := ioutil.ReadFile("./config.yaml")
	if err != nil {
		t.Fatalf("Read: %v", err)
	}

	config := &RawConfig{}
	err = yaml.Unmarshal(raw, config)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}

	for i := range config.Proxy {
		config.Proxy[i]["v6"] = true
	}

	file, _ := os.Create("./www.yaml")
	en := yaml.NewEncoder(file)
	en.Encode(config)
}