#!/usr/bin/env python3
"""LEESSH desktop URL-link CLI manager.

Kept for command-line use; the web admin page at
http://127.0.0.1:9089/admin is the recommended UI.
"""
import json
import os
import sys

CONFIG = "/opt/gmssh-links/links.json"
DESKTOP_DIR = "/.__gmssh/desktop"
ADMIN_URL = "http://127.0.0.1:9089/admin"


def load():
    if not os.path.exists(CONFIG):
        return {"links": []}
    with open(CONFIG) as f:
        return json.load(f)


def show():
    data = load()
    links = data["links"]
    if not links:
        print("no links configured")
    print(f"{'name':<20} {'title':<16} {'port':<6} url")
    for x in links:
        print(f"{x.get('name',''):<20} {x.get('title',''):<16} {x.get('port',''):<6} {x.get('url','')}")
    print(f"\n管理界面: {ADMIN_URL}  (或 LEESSH 桌面「网址快捷方式」图标)")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "list":
        show()
    else:
        print("用法: gmssh-link list")
        print(f"推荐使用 Web 管理界面: {ADMIN_URL}")
