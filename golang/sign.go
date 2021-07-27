package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/url"
	"os"
	"time"
)

/*
https://ikuuu.co 签到
*/

const (
	ikuuu = "https://ikuuu.co"
)

func login(email, passwd string) error {
	u := ikuuu + "/auth/login"
	value := url.Values{}
	value.Set("email", email)
	value.Set("passwd", passwd)
	value.Set("code", "")

	header := map[string]string{
		"content-type": "application/x-www-form-urlencoded",
	}

	raw, err := POST(u, value.Encode(), header)
	var result struct {
		Ret int    `json:"ret"`
		Msg string `json:"msg"`
	}
	err = json.Unmarshal(raw, &result)
	fmt.Println(result.Ret, result.Msg)
	if err != nil {
		return err
	}
	if result.Ret != 1 {
		return errors.New(result.Msg)
	}

	return nil
}

func sign() error {
	u := ikuuu + "/user/checkin"
	header := map[string]string{
		"accept": "application/json, text/javascript",
	}
	raw, err := POST(u, "", header)
	var result struct {
		Ret int    `json:"ret"`
		Msg string `json:"msg"`
	}
	err = json.Unmarshal(raw, &result)
	fmt.Println(result.Ret, result.Msg)
	if err != nil {
		return err
	}
	if result.Ret != 1 {
		return errors.New(result.Msg)
	}

	return nil
}

func main() {
	email := flag.String("u", "", "ikuuu email")
	passwd := flag.String("p", "", "ikuuu passwrd")
	flag.Parse()
	if *email == "" || *passwd == "" {
		fmt.Println("invalid email or passwd")
		os.Exit(1)
	}
	err := login(*email, *passwd)
	if err != nil {
		fmt.Println("login err:", err)
		os.Exit(1)
	}

	err = sign()
	if err != nil {
		fmt.Println("sign err:", err)
		os.Exit(1)
	}

	fmt.Printf("[%v] signn success!\n", time.Now().Format("2006-01-02T15:04:05Z"))
}
