package main

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"time"

	"github.com/mxk/go-imap/imap"
)

// https://datatracker.ietf.org/doc/html/rfc3501#section-6.4.5
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
	for _, config := range configs {
		fmt.Println("job config:", config.Name)
		fmt.Printf("date range: [%s -> %s]\n", config.Since, config.Before)
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

	_, err := handle(e.client.Select("INBOX", false))
	if err != nil {
		return err
	}

	before := "BEFORE " + end.Format("02-Jan-2006")
	since := "SINCE " + start.Format("02-Jan-2006")
	fmt.Println(before, since)
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

	uids = uids[:5]
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
			envelope := fileds["ENVELOPE"]
			flags := fileds["FLAGS"]
			text := fileds["RFC822.TEXT"]

			_, _ = text, envelope
			fmt.Println(imap.AsList(envelope))

			fmt.Println(flags)
			//header := imap.AsBytes(msgFields["BODY[]"])
			//if msg, _ := mail.ReadMessage(bytes.NewReader(header)); msg != nil {
			//	m.debg.Println("CheckNewMails:PostMail")
			//	if err := m.PostMail(msg); err != nil {
			//		return err
			//	}
			//	postmail = true
			//}
		}
	}

	//for msg := range ch {
	//	message, err := e.ParseMessage(msg)
	//	if err != nil {
	//		continue
	//	}
	//	e.handleMessage(message, conds)
	//}
	//

	return nil
}

func handle(cmd *imap.Command, err error) (*imap.Response, error) {
	if err == nil {
		return cmd.Result(imap.OK)
	}

	return nil, err
}

//
//const (
//	HeaderType   = "Content-Type"
//	HeaderCoding = "Content-Transfer-Encoding"
//)
//
//type Message struct {
//	Date    time.Time
//	From    string
//	To      string
//	Subject string
//	Body    string
//	Origin  *imap.Message
//}
//
//func (e *Email) ParseMessage(message *imap.Message) (msg Message, err error) {
//	env := message.Envelope
//	msg.Subject = env.Subject
//	msg.Date = env.Date
//	msg.To = env.To[0].MailboxName + "@" + env.To[0].HostName
//	msg.From = env.From[0].MailboxName + "@" + env.From[0].HostName
//	msg.Origin = message
//
//	for _, val := range message.Body {
//		var buf bytes.Buffer
//		io.Copy(&buf, val)
//		backup := buf.String()
//		reader := bufio.NewReader(&buf)
//		var (
//			line, ctype, coding, data string
//			begin                     bool
//		)
//		brline, err := reader.ReadString('\n')
//		for err == nil && line != brline {
//			if begin {
//				data += line
//			}
//			if strings.HasPrefix(line, HeaderType) {
//				ctype = strings.Split(line, ":")[1]
//				ctype = strings.TrimSpace(ctype)
//			}
//			if strings.HasPrefix(line, HeaderCoding) {
//				coding = strings.Split(line, ":")[1]
//				coding = strings.TrimSpace(coding)
//				begin = true
//			}
//			line, err = reader.ReadString('\n')
//		}
//		if err != nil && err != io.EOF {
//			return msg, err
//		}
//
//		// base64, quoted-printable
//		var raw []byte
//		data = strings.TrimSpace(data)
//		if coding == "base64" {
//			raw, err = base64.StdEncoding.DecodeString(data)
//		} else if coding == "quoted-printable" {
//			var reader io.Reader
//			reader = quotedprintable.NewReader(bytes.NewBufferString(data))
//			if strings.Contains(ctype, "gbk") {
//				reader = transform.NewReader(reader, simplifiedchinese.GBK.NewEncoder())
//			}
//			raw, err = ioutil.ReadAll(reader)
//		} else {
//			raw, err = []byte(backup), nil
//		}
//
//		msg.Body = string(raw)
//		return msg, err
//	}
//
//	return msg, errors.New("invalid body")
//}
//
//func (e *Email) handleMessage(message Message, conds []condition) {
//	for _, cond := range conds {
//		ts := message.Date.Unix()
//		if cond.start.Unix() < ts && ts < cond.end.Unix() &&
//			match(message.From, cond.rfrom) &&
//			match(message.Body, cond.rbody) &&
//			match(message.Subject, cond.rsubj) {
//			switch cond.operate.Type {
//			case OPDEL:
//				e.delete(message)
//			case OPREAD:
//				e.seen(message)
//			case OPMOVE:
//				e.move(message, cond)
//			}
//		}
//	}
//}
//
//func (e *Email) seen(message Message) {
//	fmt.Printf("tag mail to READ from [%v].\n", message.From)
//	cmd := Tag{Uid: message.Origin.Uid, Value: "\\Seen"}
//	e.client.Execute(cmd, nil)
//}
//
//func (e *Email) delete(message Message) {
//	fmt.Printf("delete mail from [%v] [%v].\n", message.From, message.Subject)
//	set := new(imap.SeqSet)
//	set.AddNum(message.Origin.Uid)
//	err := e.client.UidStore(set, "+FLAGS", `(\Deleted)`, make(chan *imap.Message))
//	fmt.Println(err)
//	ch := make(chan uint32, 1)
//	ch <- message.Origin.Uid
//	go func() {
//		e.client.Expunge(ch)
//	}()
//}
//
//func (e *Email) move(message Message, cond condition) {
//	fmt.Printf("move mails from [%v]\n", message.From)
//	set := new(imap.SeqSet)
//	set.AddNum(message.Origin.Uid)
//	cmd := commands.Copy{
//		SeqSet:  set,
//		Mailbox: cond.operate.MailBox,
//	}
//	e.client.Execute(&cmd, nil)
//	e.delete(message)
//}
//
//type Tag struct {
//	Uid   uint32
//	Value string
//}
//
//func (e Tag) Command() *imap.Command {
//	set := new(imap.SeqSet)
//	set.AddNum(e.Uid)
//	store := &commands.Store{
//		SeqSet: set,
//		Item:   imap.AddFlags,
//		Value:  e.Value,
//	}
//	return store.Command()
//}

func main() {
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
        "from": ["no-reply@accounts.google.com"],
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
    }]`

	var configs []config
	json.Unmarshal([]byte(cfg), &configs)
	fmt.Println("len", len(configs))

	e := Email{
		Username: "",
		Password: "",
	}

	err := e.Login()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	e.Handle(configs)
}
