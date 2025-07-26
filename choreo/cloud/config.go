package main

import (
	"os"
	"strconv"
	"sync"
)

type Config struct {
	// Env sets the environment the service is running in.
	// This is used in health check endpoint to indicate the environment.
	Env string
	// Hostname sets the hostname of the running service.
	// This is used to generate the Swagger host URL.
	Hostname string
	// Port sets the port of the running service.
	Port int
}

const (
	DefaultPort     = 8080
	DefaultHostname = "localhost"
)

var (
	EnvName  = "ENV"
	Hostname = "HOSTNAME"
	Port     = "PORT"
	once     sync.Once
)

var config Config

func GetConfig() *Config {
	once.Do(func() {
		loadConfig()
	})
	return &config
}

func loadConfig() (*Config, error) {
	getEnvInt := func(key string, defaultVal int) int {
		s := os.Getenv(key)
		if s == "" {
			return defaultVal
		}
		v, err := strconv.Atoi(s)
		if err != nil {
			return defaultVal
		}
		return v
	}

	getEnvString := func(key string, defaultVal string) string {
		s := os.Getenv(key)
		if s == "" {
			return defaultVal
		}
		return s
	}
	config = Config{
		Hostname: getEnvString(Hostname, DefaultHostname),
		Port:     getEnvInt(Port, DefaultPort),
		Env:      os.Getenv(EnvName),
	}
	return &config, nil
}
