#!/usr/bin/env python3
"""LEESSH URL link server.

- Dynamic multi-port 302 redirect: each link owns a port.
- Built-in admin page on ADMIN_PORT to add/remove links.
- Auto-generates LEESSH desktop shortcut (.gmk) icons.
"""
import json
import os
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = "/opt/gmssh-links/links.json"
DESKTOP_DIR = "/.__gmssh/desktop"
ADMIN_PORT = 9089
LOCK = threading.Lock()

state = {"links": []}
servers = {}  # port -> ThreadingHTTPServer


# ---------------------------------------------------------------- data

def load():
    if os.path.exists(CONFIG):
        with open(CONFIG) as f:
            try:
                return json.load(f).get("links", [])
            except Exception:
                return []
    return []


def save():
    with open(CONFIG, "w") as f:
        json.dump({"links": state["links"]}, f, indent=2, ensure_ascii=False)


def gmk_path(name):
    return os.path.join(DESKTOP_DIR, f"urllink_{name.replace('/', '_')}.gmk")


DEFAULT_ICON = "http://api.gm.cn/up/0/pics/20251203/65dc6046d3981db1bc127fbbd55cc045.png"


def gen_gmk(name, title, port, icon=None):
    data = {
        "name": f"urllink/{name}",
        "title": title,
        "icon": icon or DEFAULT_ICON,
        "type": 5,
        "key": f"urllink/{name}",
        "v": str(port),
        "sort": 0,
        "version": "1.0.0",
        "min_width": "660",
        "min_height": "400",
        "comm_type": "",
    }
    with open(gmk_path(name), "w") as f:
        f.write(json.dumps(data, ensure_ascii=False))


def remove_gmk(name):
    p = gmk_path(name)
    if os.path.exists(p):
        os.remove(p)


# ---------------------------------------------------------------- servers

class RedirectHandler(BaseHTTPRequestHandler):
    link = None

    def log_message(self, *args):
        pass

    def do_GET(self):
        target = self.link.get("url")
        if self.path == "/status":
            body = json.dumps({"port": self.server.server_address[1], "target": target}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(302)
        self.send_header("Location", target)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    do_HEAD = do_GET


def start_redirect(link):
    port = int(link["port"])
    handler = type("Handler", (RedirectHandler,), {"link": link})
    srv = ThreadingHTTPServer(("127.0.0.1", port), handler)
    servers[port] = srv
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"link '{link['name']}' port {port} -> {link['url']}")


def stop_redirect(port):
    srv = servers.pop(port, None)
    if srv:
        srv.shutdown()
        srv.server_close()


# ---------------------------------------------------------------- admin page

PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LEESSH 网址快捷方式管理</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         background: linear-gradient(135deg,#1e1e2e,#313244); color: #cdd6f4;
         min-height: 100vh; padding: 40px 20px; }
  .card { max-width: 720px; margin: 0 auto; background: #181825; border-radius: 12px;
          padding: 28px; box-shadow: 0 8px 32px rgba(0,0,0,.4); }
  h1 { font-size: 22px; margin-bottom: 6px; color: #fff; }
  .sub { color: #a6adc8; font-size: 13px; margin-bottom: 24px; }
  form { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  input, button { font-size: 14px; padding: 10px 12px; border-radius: 8px; border: 1px solid #45475a; }
  input { background: #11111b; color: #cdd6f4; outline: none; }
  input:focus { border-color: #89b4fa; }
  button { cursor: pointer; }
  .add-btn { grid-column: 1 / -1; background: #89b4fa; color: #11111b; font-weight: 600;
             border: none; } .add-btn:hover { background: #74c7ec; }
  .hint { grid-column: 1 / -1; font-size: 12px; color: #a6adc8; }
  table { width: 100%; margin-top: 22px; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid #313244; }
  th { color: #a6adc8; font-weight: 500; }
  td.url { color: #89dceb; word-break: break-all; }
  .del { background: transparent; color: #f38ba8; border: none; cursor: pointer;
         font-size: 13px; padding: 4px 8px; } .del:hover { text-decoration: underline; }
  .msg { display: none; margin-top: 12px; padding: 10px 12px; border-radius: 8px; font-size: 13px; }
  .msg.ok { display:block; background:#1e3b2f; color:#a6e3a1; }
  .msg.err { display:block; background:#3b1e1e; color:#f38ba8; }
  .icon { width: 28px; height: 28px; border-radius: 6px; vertical-align: middle;
          object-fit: contain; background:#11111b; }
  .icon-row { width: 40px; }
</style>
</head>
<body>
<div class="card">
  <h1>🌐 LEESSH 网址快捷方式</h1>
  <div class="sub">在此添加网址后，会自动在 LEESSH 桌面生成一个可点击的快捷图标。<br>
  添加完成后，在 LEESSH 桌面刷新或重新登录即可看到新图标。</div>

  <form onsubmit="addLink(event)">
    <input id="name" placeholder="名称（如：我的博客）" required>
    <input id="url" placeholder="网址（如：https://example.com）" required>
    <input id="icon" placeholder="图标 URL（选填，如 https://xxx/icon.png）">
    <div class="hint">提示：名称后加冒号可设桌面显示名，如：博客:我的博客。图标留空则用默认图标。</div>
    <button class="add-btn" type="submit">＋ 新建桌面网址</button>
  </form>

  <div id="msg" class="msg"></div>

  <table>
    <thead><tr><th>图标</th><th>名称</th><th>端口</th><th>网址</th><th></th></tr></thead>
    <tbody id="rows"></tbody>
  </table>
</div>
<script>
function show(msg, ok) {
  var m = document.getElementById('msg');
  m.className = 'msg ' + (ok ? 'ok' : 'err');
  m.textContent = msg;
  setTimeout(function(){ m.className = 'msg'; }, 4000);
}
async function api(path, body) {
  var r = await fetch(path, { method:'POST', headers:{'Content-Type':'application/json'},
                             body: JSON.stringify(body || {}) });
  return r.json();
}
async function addLink(ev) {
  ev.preventDefault();
  var name = document.getElementById('name').value.trim();
  var url = document.getElementById('url').value.trim();
  var icon = document.getElementById('icon').value.trim();
  if (!name || !url) return show('请填写名称和网址', false);
  var r = await api('/api/links/add', { name: name, url: url, icon: icon });
  if (r.ok) { show('已创建 "' + r.title + '" 桌面图标，刷新 LEESSH 桌面即可看到', true);
              document.getElementById('name').value='';
              document.getElementById('url').value='';
              document.getElementById('icon').value='';
              load(); }
  else show(r.error || '添加失败', false);
}
async function delLink(btn) {
  var name = btn.getAttribute('data-name');
  if (!confirm('删除 "' + name + '" 及桌面图标？')) return;
  var r = await api('/api/links/remove', { name: name });
  if (r.ok) { show('已删除', true); load(); }
  else show(r.error || '删除失败', false);
}
async function load() {
  var r = await fetch('/api/links/list');
  var data = await r.json();
  var tb = document.getElementById('rows');
  tb.innerHTML = '';
  data.links.forEach(function(l) {
    var tr = document.createElement('tr');
    tr.innerHTML = '<td><img class="icon" src="' + (l.icon || '') + '" onerror="this.remove()"></td>'
      + '<td>' + escapeHtml(l.title) + '</td>'
      + '<td>' + l.port + '</td>'
      + '<td class="url">' + escapeHtml(l.url) + '</td>'
      + '<td><button class="del" data-name="' + l.name.replace(/"/g,'') + '" onclick="delLink(this)">删除</button></td>';
    tb.appendChild(tr);
  });
}
function escapeHtml(s) { return (s||'').replace(/[&<>"']/g, function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }
load();
</script>
</body>
</html>
"""


class AdminHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/admin" or self.path == "/":
            body = PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/links/list":
            self._json(200, {"links": state["links"]})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        try:
            ln = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(ln) if ln else b"{}"
            req = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            req = {}
        with LOCK:
            if self.path == "/api/links/add":
                name = (req.get("name") or "").strip()
                url = (req.get("url") or "").strip()
                icon = (req.get("icon") or "").strip()
                title = name
                if ":" in name:
                    parts = name.split(":", 1)
                    name, title = parts[0].strip(), parts[1].strip()
                if not name or not url:
                    return self._json(400, {"error": "name and url required"})
                if not (url.startswith("http://") or url.startswith("https://")):
                    return self._json(400, {"error": "url must start with http(s)://"})
                if icon and not (icon.startswith("http://") or icon.startswith("https://")):
                    return self._json(400, {"error": "icon must start with http(s)://"})
                if any(x.get("name") == name for x in state["links"]):
                    return self._json(400, {"error": f"link '{name}' already exists"})
                used = {int(x.get("port", 0)) for x in state["links"]}
                port = 9090
                while port in used or port == ADMIN_PORT:
                    port += 1
                link = {"name": name, "title": title, "url": url, "port": port, "icon": icon}
                state["links"].append(link)
                save()
                gen_gmk(name, title, port, icon or None)
                start_redirect(link)
                return self._json(200, {"ok": True, "title": title, "port": port})
            elif self.path == "/api/links/remove":
                name = (req.get("name") or "").strip()
                for i, x in enumerate(state["links"]):
                    if x.get("name") == name:
                        stop_redirect(int(x["port"]))
                        state["links"].pop(i)
                        save()
                        remove_gmk(name)
                        return self._json(200, {"ok": True})
                return self._json(404, {"error": f"link '{name}' not found"})
        self._json(404, {"error": "not found"})


def main():
    state["links"] = load()
    for link in state["links"]:
        start_redirect(link)

    admin = ThreadingHTTPServer(("127.0.0.1", ADMIN_PORT), AdminHandler)
    print(f"admin page: http://127.0.0.1:{ADMIN_PORT}/admin")
    gen_admin_gmk()
    admin.serve_forever()


def gen_admin_gmk():
    data = {
        "name": "urllink/admin",
        "title": "网址快捷方式",
        "icon": "http://api.gm.cn/up/0/pics/20251203/65dc6046d3981db1bc127fbbd55cc045.png",
        "type": 5,
        "key": "urllink/admin",
        "v": str(ADMIN_PORT),
        "sort": 0,
        "version": "1.0.0",
        "min_width": "660",
        "min_height": "400",
        "comm_type": "",
    }
    with open(os.path.join(DESKTOP_DIR, "urllink_admin.gmk"), "w") as f:
        f.write(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
