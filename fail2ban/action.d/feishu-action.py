#!/usr/bin/env python3
"""
Fail2Ban 飞书通知脚本（V2 签名）
支持通过 Fail2Ban [Init] 配置传入 webhook_url 和 secret
"""
import sys
import json
import hmac
import hashlib
import base64
import time
import socket
from datetime import datetime, timezone
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
import argparse


def generate_sign(timestamp: str, secret: str) -> str:
    """
    生成飞书 V2 签名
    签名字符串 = timestamp + "\n" + secret
    HMAC-SHA256(key=secret, message=签名字符串) → Base64
    """
    sign_string = f"{timestamp}\n{secret}"
    hmac_code = hmac.new(
        sign_string.encode("utf-8"),
        digestmod=hashlib.sha256
    ).digest()
    return base64.b64encode(hmac_code).decode("utf-8")

def send_feishu_message(webhook_url: str, secret: str, jail: str, ip: str, action: str = "unban"):
    """
    发送飞书消息
    :param webhook_url: 飞书机器人 webhook
    :param secret: 机器人 secret
    :param jail: Fail2Ban jail 名称
    :param ip: 触发 IP
    :param action: "ban" | "unban"
    """
    timestamp = str(int(time.time()))
    sign = generate_sign(timestamp, secret)

    # 卡片样式构建
    color = "red" if action == "ban" else "green"
    title = "⚠️ Fail2Ban 封禁" if action == "ban" else "✅ Fail2Ban 解封"
    current_time = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S")
    hostname = socket.gethostname()

    card = {
        "config": {"width_mode": "compact"},
        "header": {
            "template": color,
            "title": {"content": title, "tag": "plain_text"}
        },
        "elements": [
            {"tag": "markdown", "content": f"**【Jail】** {jail}"},
            {"tag": "markdown", "content": f"**【IP】** {ip}"},
            {"tag": "markdown", "content": f"**【时间】** {current_time}"},
            {"tag": "markdown", "content": f"**【服务器】** {hostname}"},
            {"tag": "hr"},
            {
                "tag": "note",
                "elements": [
                    {"tag": "plain_text", "content": f"Fail2Ban · {hostname.upper()} · {timestamp}"}
                ]
            }
        ]
    }

    payload = {
        "timestamp": timestamp,
        "sign": sign,
        "msg_type": "interactive",
        "card": card
    }

    # 发送请求（带超时）
    try:
        req = Request(
            webhook_url.strip(),  # 移除 URL 末尾空格
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST"
        )
        with urlopen(req, timeout=5) as resp:
            result = resp.read().decode("utf-8")
            # 飞书成功响应: {"StatusCode":0}
            if '"StatusCode":0' not in result:
                print(f"⚠️ 飞书响应异常: {result}", file=sys.stderr)
    except (URLError, HTTPError, TimeoutError) as e:
        print(f"❌ 发送飞书通知失败: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Fail2Ban 飞书通知脚本")
    parser.add_argument("--webhook", required=True, help="飞书机器人 webhook URL")
    parser.add_argument("--secret", required=True, help="飞书机器人 secret")
    parser.add_argument("--jail", required=True, help="Fail2Ban jail 名称")
    parser.add_argument("--ip", required=True, help="触发操作的 IP 地址")
    parser.add_argument("--action", choices=["ban", "unban"], default="unban", help="操作类型")

    args = parser.parse_args()

    send_feishu_message(
        webhook_url=args.webhook,
        secret=args.secret,
        jail=args.jail,
        ip=args.ip,
        action=args.action
    )

if __name__ == "__main__":
    main()
