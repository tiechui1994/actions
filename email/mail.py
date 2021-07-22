import base64
import getopt
import imaplib
import email
import json
import random
import smtplib
import time
import sys
import re

from email.header import decode_header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

OK = "OK"

OP_REPLY = "reply"
OP_DEL = "delete"
OP_READ = "read"
OP_MOVE = "move"

# account credentials
username = ""
password = ""

html = """
<div>
    <div>
        {reply}
    </div>
    <blockquote style="margin:0px 0px 0px 0.8ex;
        border-left:2px solid rgb({r},{g},{b});
        padding-left:1ex">
        {origin}
    </blockquote>
<div>
"""
plain = """
{reply}
{origin}
"""


def get_text_payload(msg: email.message.Message) -> dict:
    encode = msg.get("Content-Transfer-Encoding", None)
    payload = msg.get_payload()
    if encode and encode == "base64":
        return {
            "type": msg.get_content_subtype(),
            "data": base64.standard_b64decode(payload).decode('utf-8', errors='ignore'),
        }
    else:
        return {
            "type": msg.get_content_subtype(),
            "data": payload,
        }


def get_multipart_payload(msg: email.message.Message) -> dict:
    ans = list()
    for part in msg.get_payload():
        ans.append(get_text_payload(part))

    return {
        "type": "multipart",
        "data": ans
    }


def get_plain_body(msg: email.message.Message) -> str:
    body = ''
    maintype = msg.get_content_maintype()
    if maintype == "multipart":
        multi = get_multipart_payload(msg).get("data", [])
        for text in multi:
            if text.get("type") == "html":
                body = text.get("data", "")
            if text.get("type") == "plain" and body == "":
                body = text.get("data", "")
    elif maintype == "text":
        body = get_text_payload(msg).get("data", "")

    return body


def get_body(message: email.message.Message) -> dict:
    body = {}
    maintype = message.get_content_maintype()
    if maintype == "multipart":
        body = get_multipart_payload(message)
    elif maintype == "text":
        body = get_text_payload(message)

    return body


def get_header(message: email.message.Message, field: str) -> str:
    value = message.get(field, None)
    if not value:
        return ''
    try:
        tokens = decode_header(value)
        if len(tokens) == 0:
            return ''

        value = ''
        for token in tokens:
            subject = token[0]
            encode = token[1]
            if not encode or encode in ["unknown-8bit"]:
                encode = "utf-8"
            if isinstance(subject, bytes):
                value += " " + subject.decode(encoding=encode)
            elif isinstance(subject, str):
                value += " " + subject
    except Exception as err:
        print(err)

    return value.lstrip(" ")


def login() -> imaplib.IMAP4_SSL:
    # create an POP class with SSL
    ssl = imaplib.IMAP4_SSL("imap.qq.com", port=993)
    # authenticate
    status, data = ssl.login(username, password)
    if status != OK:
        print(data)
        exit(1)

    # select the mailbox I want to delete in
    # if you want SPAM, use imap.select("SPAM") instead
    status, data = ssl.select("INBOX")
    if status != OK:
        print(data)
        exit(1)

    return ssl


def close(imap: imaplib.IMAP4):
    # close the mailbox
    imap.close()
    # logout from the account
    imap.logout()


def tag(imap: imaplib.IMAP4_SSL, mail: bytes, flags: str):
    return imap.store(mail, "+FLAGS", flags)


def remove(imap: imaplib.IMAP4_SSL, mail: bytes):
    tag(imap, mail, "\\Deleted")
    return imap.expunge()


def move(imap: imaplib.IMAP4_SSL, mail: bytes, folder: str):
    result = imap.copy(mail, folder)
    if result[0] == OK:
        return remove(imap, mail)
    return result


def readed(imap: imaplib.IMAP4_SSL, mail: bytes):
    return tag(imap, mail, "\\Seen")


def default_reply_message(mail: email.message.Message) -> str:
    sender = get_header(mail, "From")
    match = re.search(r'<(.*?)@.*?>', sender, re.IGNORECASE)
    if match:
        return "Hello, " + match.groups()[0]
    else:
        return "Hello, " + sender


def reply(mail: email.message.Message, config: dict):
    new = MIMEMultipart("alternative")
    new["Date"] = time.strftime("%a, %d %b %Y %H:%M:%S +0800 (CST)")
    new["Message-ID"] = email.utils.make_msgid()
    new["In-Reply-To"] = mail["Message-ID"]
    new["Subject"] = "Re: " + mail["Subject"]
    new["To"] = mail["Reply-To"] or mail["From"]
    new["From"] = mail["To"]

    reply_message = default_reply_message(mail)
    plainbody = config.get("body", reply_message)
    htmlbody = config.get("body", "<div>" + reply_message + "</div>")

    origin = get_body(mail)
    originplain = ""
    originhtml = ""
    maintype = origin.get("type")
    if maintype == "plain":
        originplain += origin.get("data") + "\n"
    elif maintype == "html":
        originhtml += origin.get("data") + "<br>"
    elif maintype == "multipart":
        data = origin.get("data", [{}, {}])
        for idx in data:
            typ = idx.get("type")
            maintype = (lambda x: x if maintype == "multipart" else maintype)(typ)
            if typ == "plain":
                originplain += idx.get("data", "") + "\n"
            elif typ == "html":
                originhtml += idx.get("data", "") + "<br>"
    else:
        maintype = "plain"

    if maintype == "html":
        originhtml = originhtml[:-len("<br>")]
        r, g, b = random.sample(range(1, 255), 3)
        body = html.format(reply=htmlbody, origin=originhtml, r=r, g=g, b=b)
        new.attach(MIMEText(body, "html", "UTF-8"))
    else:
        originplain = originplain[:-len("\n")]
        body = plain.format(reply=plainbody, origin=originplain)
        new.attach(MIMEText(body, "plain", "UTF-8"))

    print(json.dumps(get_body(new),
                     ensure_ascii=False,
                     sort_keys=False,
                     indent=3,
                     separators=(", ", ": ")))

    from html.parser import HTMLParser
    body = get_body(mail)
    if body.get("type") == "multipart":
        print(HTMLParser().unescape(body.get("data")[0]))
    elif body.get("type") == "text":
        print(HTMLParser().unescape(body.get("data")))

    s = smtplib.SMTP("smtp.qq.com", 587)
    result = s.login(username, password)
    print(result)
    result = s.sendmail(mail["To"], [new["To"]], new.as_string())
    print(result)
    s.quit()


def regex(rules):
    if isinstance(rules, list):
        ans = []
        for r in rules:
            ans.append(re.compile(r, flags=re.IGNORECASE | re.UNICODE | re.MULTILINE))
        return ans
    elif isinstance(rules, str):
        return re.compile(rules, flags=re.IGNORECASE | re.UNICODE | re.MULTILINE)
    else:
        return re.compile('', flags=re.IGNORECASE | re.UNICODE | re.MULTILINE)


def match(rules, data: str) -> bool:
    if isinstance(rules, list):
        for r in rules:
            if r.search(data):
                return True
        return False
    else:
        return rules.search(data) is not None


# search for attr(FROM/SUBJECT/TO/CC)
# status, messages = imap.search(None, "FROM <925184024@qq.com>")
# search for header
# status, messages = imap.search(None, "HEADER Message-ID "xxxx"")
# search for status
# status, messages = imap.search(None, "(UNSEEN)")
# seach ALL
# status, messages = imap.search(None, "ALL")
# search for date(BEFORE/AFTER)
# status, messages = imap.search(None, "BEFORE "01-JAN-2020"")
def handle(imap: imaplib.IMAP4_SSL, config: list):
    condition = list()
    starttime = '9999-12-31'
    endtime = '0000-00-00'
    for c in config:
        print("job config:", c.get("name"))
        now = time.strftime("%Y-%m-%d")
        start = time.strftime("%Y-%m-%d", time.strptime(c.get("since", now), "%Y-%m-%d"))
        end = time.strftime("%Y-%m-%d", time.strptime(c.get("before", now), "%Y-%m-%d"))
        print("date range: [%s -> %s]" % (start, end))
        starttime = min(starttime, start)
        endtime = max(endtime, end)
        condition.append({
            "start": start,
            "end": end,
            "rbody": regex(c.get("body")),
            "rfrom": regex(c.get("from")),
            "rsubj": regex(c.get("subject")),
            "type": c.get("op", {}).get("type"),
        })

    # mails
    start = time.strftime("%d-%b-%Y", time.strptime(starttime, "%Y-%m-%d"))
    end = time.strftime("%d-%b-%Y", time.strptime(endtime, "%Y-%m-%d"))
    status, messages = imap.search(None, 'SINCE "%s"' % (start,), 'BEFORE "%s"' % (end,))
    if status != OK:
        print("search failure", status)
        return

    messages = messages[0]
    if messages == b'':
        print("no emails")
        return

    # convert messages to a list of email IDs
    messages = messages.split(b" ")
    print("total mails: %d" % (len(messages)))

    for uid in messages:
        _, data = imap.fetch(uid, "(RFC822)")
        # you can delete the for loop for performance if you have a long list of emails
        # because it is only for printing the SUBJECT of target email to delete
        for response in data:
            if isinstance(response, tuple):
                #  tuple, 0: RFC 1: msg
                message = email.message_from_bytes(response[1])
                # decode the email subject

                body = get_plain_body(message)
                subject = get_header(message, "Subject")
                sender = get_header(message, "From")
                to = get_header(message, "To")
                date = get_header(message, "Date")

                for cond in condition:
                    # date
                    try:
                        start = cond.get("start")
                        end = cond.get("end")
                        if date.endswith(" (CST)"):
                            date = date[0:-6]
                        # Tue, 9 Mar 2021 19:10:03 +0800 (CST)
                        style = "%a, %d %b %Y %H:%M:%S %z"
                        day = time.strftime("%Y-%m-%d", time.strptime(date, style))
                        if day < start or day > end:
                            continue
                    except ValueError:
                        continue

                    # regex
                    rbody = cond.get("rbody")
                    rfrom = cond.get("rfrom")
                    rsubj = cond.get("rsubj")
                    op = cond.get("type")

                    if match(rfrom, sender) and match(rsubj, subject) and match(rbody, body):
                        if op == OP_REPLY:
                            print("[{to}] will send mail to [{send}]".format(to=to, send=sender))
                            reply(message, c.get("op", {}))
                        elif op == OP_DEL:
                            print("delete mail from [{send}]".format(send=sender))
                            remove(imap, uid)
                        elif op == OP_READ:
                            print("tag mail to READ from [{send}]".format(send=sender))
                            readed(imap, uid)
                        elif op == OP_MOVE:
                            print("move mails from [{send}]".format(send=sender))
                            move(imap, uid, c.get("folder", "INBOX"))


if __name__ == "__main__":
    argv = sys.argv[1:]

    try:
        opts, args = getopt.getopt(argv, "u:p:", ["username=", "password="])  # 长选项模式
        for opt, arg in opts:
            if opt in ["-u", "--username"]:
                username = arg
            if opt in ["-p", "--password"]:
                password = arg
    except Exception as e:
        print("param error", e)

    if not username or not password:
        print("no username or password")
        exit(1)

    client = login()
    handle(client, list([{
        "name": "github",
        "since": "2021-01-10",
        "before": "2022-04-18",
        "from": ["github.com"],
        "body": ["jobs have failed", "refs/heads",
                 "No jobs were run", "Successfully deployed",
                 "Deployment failed", "A personal access token"],
        "op": {
            "type": OP_DEL
        }
    }, {
        "name": "google",
        "since": "2021-01-10",
        "before": "2022-04-18",
        "from": ["no-reply@accounts.google.com"],
        "subject": ["安全提醒", "帐号的安全性"],
        "op": {
            "type": OP_DEL
        }
    }, {
        "name": "jd",
        "since": "2021-01-10",
        "before": "2022-04-18",
        "from": ["newsletter1@jd.com"],
        "op": {
            "type": OP_DEL
        }
    }]))
    close(client)
