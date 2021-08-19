package main

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"mime"
	"os"
	"regexp"
	"time"

	"github.com/mxk/go-imap/imap"
)

// https://datatracker.ietf.org/doc/html/rfc3501
// https://vimsky.com/zh-tw/examples/detail/golang-ex-github.com.mxk.go-imap.imap-Command---class.html

type Email struct {
	Username string
	Password string
	client   *imap.Client
}

type operate struct {
	Type    string `json:"type"`
	MailBox string `json:"mailbox"`
}

type config struct {
	Name    string    `json:"name"`
	Since   time.Time `json:"since"`
	Before  time.Time `json:"before"`
	From    []string  `json:"from"`
	Body    []string  `json:"body"`
	Subject []string  `json:"subject"`
	Operate operate   `json:"op"`
}

type condition struct {
	start   time.Time
	end     time.Time
	rbody   []*regexp.Regexp
	rfrom   []*regexp.Regexp
	rsubj   []*regexp.Regexp
	operate operate
}

const (
	OPDEL  = "delete"
	OPREAD = "read"
	OPMOVE = "move"
)

func regex(str []string) []*regexp.Regexp {
	var ans = make([]*regexp.Regexp, len(str))
	for i := range str {
		ans[i] = regexp.MustCompile(str[i])
	}
	if len(ans) == 0 {
		ans = append(ans, regexp.MustCompile(".*"))
	}

	return ans
}

func match(str string, r []*regexp.Regexp) bool {
	for _, v := range r {
		if v.MatchString(str) {
			return true
		}
	}

	return false
}

func (e *Email) Login() error {
	var err error
	e.client, err = imap.DialTLS("imap.qq.com:993", &tls.Config{
		ServerName: "imap.qq.com",
	})
	if err != nil {
		return err
	}

	_, err = e.client.Login(e.Username, e.Password)
	if err != nil {
		return err
	}

	return nil
}

func (e *Email) Handle(configs []config) error {
	var conds []condition
	start := time.Now().Add(10 * 365 * 24 * time.Hour)
	end := time.Unix(0, 0)

	now := time.Now()
	format := "2006-01-02"
	for _, config := range configs {
		fmt.Println("job config:", config.Name)
		fmt.Printf("date range: [%s -> %s]\n", config.Since.Format(format), config.Before.Format(format))
		if config.Since.After(now) {
			config.Since = now
		}
		if config.Before.Before(now) {
			config.Before = now
		}

		if start.After(config.Since) {
			start = config.Since
		}
		if end.Before(config.Before) {
			end = config.Before
		}
		conds = append(conds, condition{
			start:   config.Since,
			end:     config.Before,
			rbody:   regex(config.Body),
			rfrom:   regex(config.From),
			rsubj:   regex(config.Subject),
			operate: config.Operate,
		})
	}

	if len(configs) == 0 {
		start, end = end, start
	}

	_, err := imap.Wait(e.client.Select("INBOX", false))
	if err != nil {
		return err
	}

	before := "BEFORE " + end.Format("02-Jan-2006")
	since := "SINCE " + start.Format("02-Jan-2006")
	cmd, err := imap.Wait(e.client.UIDSearch(before, since))
	if err != nil {
		return err
	}

	uids := make([]uint32, 0, 100)
	for _, response := range cmd.Data {
		for _, uid := range response.SearchResults() {
			uids = append(uids, uid)
		}
	}

	fmt.Println("mail len:", len(uids))
	set := new(imap.SeqSet)
	for _, uid := range uids {
		set.Clear()
		set.AddNum(uid)
		cmd, err = imap.Wait(e.client.UIDFetch(set, "FLAGS", "ENVELOPE", "RFC822.TEXT"))
		if err != nil {
			fmt.Println(err)
			return err
		}

		for cmd.InProgress() {
			e.client.Recv(-1)
		}
		for _, response := range cmd.Data {
			fileds := response.MessageInfo().Attrs
			_ = fileds["FLAGS"]
			text := fileds["RFC822.TEXT"]
			envelope := parseEnvelope(fileds["ENVELOPE"])
			e.handleMessage(uid, envelope, imap.AsString(text), conds)
		}
	}

	return nil
}

type Addr struct {
	Addr   string
	Person string
}
type Envelope struct {
	Date      time.Time
	Subject   string
	From      []Addr
	Sender    []Addr
	ReplyTo   []Addr
	To        []Addr
	Cc        []Addr
	Bcc       []Addr
	InReplyTo string
	MessageId string
}

func parseEnvelope(field imap.Field) (envelope Envelope) {
	// date, subject, from, sender, reply-to, to, cc, bcc, in-reply-to, message-id
	list := imap.AsList(field)

	// date: Tue, 06 Apr 2021 07:36:28 -0700
	var err error
	envelope.Date, err = parseMessageDateTime(imap.AsString(list[0]))
	if err != nil {
		fmt.Println("err", err)
	}

	// subject
	envelope.Subject, _ = decodeHeader(imap.AsString(list[1]))

	// from, sender, reply-to, to, cc, bcc
	envelope.From, _ = parseAddrList(list[2])
	envelope.Sender, _ = parseAddrList(list[3])
	envelope.ReplyTo, _ = parseAddrList(list[4])
	envelope.To, _ = parseAddrList(list[5])
	envelope.Cc, _ = parseAddrList(list[6])
	envelope.Bcc, _ = parseAddrList(list[7])

	// in-reply-to, message-id
	envelope.InReplyTo = imap.AsString(list[8])
	envelope.MessageId = imap.AsString(list[9])
	return envelope
}

func parseAddrList(field imap.Field) (list []Addr, err error) {
	tokens := imap.AsList(field)
	for i := range tokens {
		// (person,domain,mailbox,host)
		values := imap.AsList(tokens[i])
		if len(values) != 4 {
			return nil, errors.New("invalid addr")
		}
		var addr Addr
		addr.Person, err = decodeHeader(imap.AsString(values[0]))
		if err != nil {
			return nil, err
		}
		addr.Addr = imap.AsString(values[2]) + "@" + imap.AsString(values[3])
		list = append(list, addr)
	}

	return list, nil
}

var CharsetReader func(charset string, r io.Reader) (io.Reader, error)
var wordDecoder = &mime.WordDecoder{
	CharsetReader: func(charset string, input io.Reader) (io.Reader, error) {
		if CharsetReader != nil {
			return CharsetReader(charset, input)
		}
		return nil, fmt.Errorf("imap: unhandled charset %q", charset)
	},
}

func decodeHeader(s string) (string, error) {
	dec, err := wordDecoder.DecodeHeader(s)
	if err != nil {
		return s, err
	}
	return dec, nil
}

var envelopeDateTimeLayouts = [...]string{
	"Mon, 02 Jan 2006 15:04:05 -0700", // popular, try it first
	"Mon, 02 Jan 2006 15:04:05 MST",
	"Mon, 2 Jan 2006 15:04:05 -0700",
}

var commentRE = regexp.MustCompile(`[ \t]+\(.*\)$`)

func parseMessageDateTime(maybeDate string) (time.Time, error) {
	maybeDate = commentRE.ReplaceAllString(maybeDate, "")
	for _, layout := range envelopeDateTimeLayouts {
		parsed, err := time.Parse(layout, maybeDate)
		if err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, fmt.Errorf("date %s could not be parsed", maybeDate)
}

func encodeHeader(s string) string {
	return mime.QEncoding.Encode("utf-8", s)
}

func (e *Email) handleMessage(uid uint32, envelop Envelope, body string, conds []condition) {
	for _, cond := range conds {
		ts := envelop.Date.Unix()
		if cond.start.Unix() < ts && ts < cond.end.Unix() &&
			match(envelop.From[0].Addr, cond.rfrom) &&
			match(body, cond.rbody) &&
			match(envelop.Subject, cond.rsubj) {
			switch cond.operate.Type {
			case OPDEL:
				e.delete(uid, envelop)
			case OPREAD:
				e.seen(uid, envelop)
			case OPMOVE:
				e.move(uid, envelop, cond)
			}
		}
	}
}

func (e *Email) seen(uid uint32, envelop Envelope) {
	fmt.Printf("tag mail to READ from [%v].\n", envelop.From[0].Addr)
	set := new(imap.SeqSet)
	set.AddNum(uid)
	imap.Wait(e.client.UIDStore(set, "+FLAGS", "\\Seen"))
}

func (e *Email) delete(uid uint32, envelop Envelope) {
	fmt.Printf("delete mail from [%v] [%v].\n", envelop.From[0].Addr, envelop.Subject)
	set := new(imap.SeqSet)
	set.AddNum(uid)
	imap.Wait(e.client.UIDStore(set, "+FLAGS", "\\Deleted"))
	imap.Wait(e.client.Expunge(set))
}

func (e *Email) move(uid uint32, envelop Envelope, cond condition) {
	fmt.Printf("move mails from [%v]\n", envelop.From[0].Addr)
	set := new(imap.SeqSet)
	set.AddNum(uid)
	imap.Wait(e.client.UIDCopy(set, cond.operate.MailBox))
	e.delete(uid, envelop)
}

func (e *Email) reply(uid uint32, envelop Envelope, cond condition) {

}

func main() {
	username := flag.String("u", "", "username")
	password := flag.String("p", "", "password")
	flag.Parse()
	if *username == "" || *password == "" {
		fmt.Println("no username or password")
		os.Exit(1)
	}

	cfg := `[{
        "name": "github",
        "since": "2021-01-10T00:00:00Z",
        "before": "2022-04-18T00:00:00Z",
        "from": ["github.com"],
        "body": ["jobs have failed", "refs/heads", "All jobs were cancelled",
                 "No jobs were run", "Successfully deployed",
                 "Deployment failed", "A personal access token"],
        "op": {
            "type": "delete"
        }
    }, {
        "name": "google",
        "since": "2021-01-10T00:00:00Z",
        "before": "2022-04-18T00:00:00Z",
        "from": ["accounts.google.com"],
        "subject": ["安全提醒", "帐号的安全性"],
        "op": {
           "type": "delete"
        }
    }, {
        "name": "jd",
        "since": "2021-01-10T00:00:00Z",
        "before": "2022-04-18T00:00:00Z",
        "from": ["newsletter1@jd.com"],
        "op": {
            "type": "delete"
        }
    }, {
		"name": "hkisl",
 	    "since": "2021-01-10T00:00:00Z",
        "before": "2022-04-18T00:00:00Z",
		"from": ["noreply-wms@hkisl.net"],
        "op": {
            "type": "delete"
        }
	}, {
		"name": "qovery",
 	    "since": "2021-01-10T00:00:00Z",
        "before": "2022-04-18T00:00:00Z",
		"from": ["qovery.com"],
        "op": {
            "type": "delete"
        }
	}]`

	var configs []config
	err := json.Unmarshal([]byte(cfg), &configs)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	e := Email{
		Username: *username,
		Password: *password,
	}

	err = e.Login()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	e.Handle(configs)
}
