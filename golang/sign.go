package main

import (
	"fmt"
	"net/url"
)

/*
https://ikuuu.co 签到
*/

const (
	ikuuu = "https://ikuuu.co"
)

func login(email, password string) error {
	u := ikuuu + "/auth/login"
	value := url.Values{}
	value.Set("email", email)
	value.Set("passwd", password)
	value.Set("code", "")

	header := map[string]string{
		"content-type": "application/x-www-form-urlencoded",
	}

	raw, err := POST(u, value.Encode(), header)
	fmt.Println(string(raw))
	return err
}

func sign() error {
	u := ikuuu + "/user/checkin"
	header := map[string]string{
		"accept": "application/json",
	}
	raw, err := POST(u, "", header)
	fmt.Println(string(raw))
	return err
}

func main() {
	login("","")
	sign()
}