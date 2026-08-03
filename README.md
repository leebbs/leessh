# LEESSH

> 基于 GMSSH 私有版的二次开发/本地化部署包

LEESSH 是一个基于 [GMSSH](https://github.com/GMSSH/GMSSH) 私有版进行的二次开发部署包，主要做了以下定制：

- **品牌改名**：界面显示名由 `GMSSH` 改为 `LEESSH`
- **去除授权提示**：移除桌面"未授权/立即授权/解锁更多高级功能"等授权相关 UI
- **扩展：桌面网址快捷方式**：新增管理界面，可在 GMSSH 桌面创建"点击打开任意网址"的快捷图标

> ⚠️ 版权声明：本包内含 GMSSH 官方私有版二进制，版权归原厂所有。本仓库仅作个人二次开发与研究用途，请勿用于商业分发。如需商业使用请购买官方授权。

---

## 目录结构

```
leessh/
├── bin/           # GMSSH 主程序（gs_main 二进制）
├── config/        # 配置（已剔除 .uuid.json 等敏感信息）
├── new_www/       # 新版 Web 前端（已改名 LEESSH + 去除授权 UI）
├── www/           # 旧版 Web 前端
├── resources/     # 语言资源
├── ga/            # GA 服务中心组件
├── deploy.sh      # 官方部署脚本
└── extensions/    # 【本仓库自主开发】扩展与配置
    ├── server.py          # 桌面网址快捷方式重定向服务
    ├── gmssh-link.py      # CLI 管理命令
    ├── gmssh.service      # systemd 服务（GMSSH 主服务）
    └── gmssh-links.service # systemd 服务（网址快捷方式服务）
```

## 快速部署

### 1. 安装 GMSSH 主程序

```bash
# 解压部署包到 /opt/gmssh
sudo mkdir -p /opt/gmssh
sudo tar xzf leessh.tar.gz -C /opt/gmssh

# 注册 systemd 服务
sudo cp extensions/gmssh.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gmssh
sudo systemctl start gmssh
```

> **注意**：首次启动前，`.uuid.json` 会由程序自动生成。配置端口可在 `config/config.json` 的 `http_port` 修改。

### 2. 安装网址快捷方式扩展

```bash
# 部署扩展服务
sudo cp extensions/gmssh-links.service /etc/systemd/system/
sudo mkdir -p /opt/gmssh-links
sudo cp extensions/server.py /opt/gmssh-links/
sudo systemctl daemon-reload
sudo systemctl enable gmssh-links
sudo systemctl start gmssh-links
```

## 桌面网址快捷方式

登录 LEESSH 桌面后，双击桌面 **"网址快捷方式"** 图标（或访问 `http://<服务器IP>:9089/admin`），即可：

1. 填写**名称**、**网址**、**图标 URL**（可留空）
2. 点击"＋新建桌面网址"
3. 刷新桌面，出现新的可点击快捷图标

### 技术原理

GMSSH 桌面图标由 `/.__gmssh/desktop/*.gmk` 文件驱动。`type:5` 的图标点击后会执行 `window.open("http://<服务器IP>:<端口>")`。本扩展利用这一机制：

- 每个网址分配一个本地端口，由 `server.py` 做 302 重定向到目标 URL
- 管理界面 API：
  - `POST /api/links/add` — 新增链接
  - `POST /api/links/remove` — 删除链接
  - `GET /api/links/list` — 列出链接

### CLI 用法

```bash
gmssh-link list   # 查看当前快捷方式
```

## 修改记录

| 文件 | 修改内容 |
|------|---------|
| `new_www/assets/index-CvlSDq92.js` | `activeStatus` 强制为已授权；品牌改名 |
| `new_www/assets/home-iIVqoH1h.js` | 去除授权状态角标；品牌改名 |
| `new_www/index.html` / `www/index.html` | 标题改为 LEESSH |
| `ga/config.json` | 服务名改为 LEESSH |
| `extensions/server.py` | 【新增】网址快捷方式重定向服务 |

## 注意事项

- **升级会被覆盖**：GMSSH 官方升级重新安装后，改名和授权补丁会被覆盖，需重新应用。
- **敏感信息**：本包已剔除 `.uuid.json`（授权标识），首次启动会重新生成。`credential.json`（登录凭据）不包含在包内。
- **小写 gmssh 技术标识**：API 域名、存储路径等仍保留原样（改动会破坏功能）。

## License

- GMSSH 核心二进制版权归 GMSSH 原厂所有
- 本仓库自主开发的扩展代码（`extensions/`）遵循 [MIT License](LICENSE)
