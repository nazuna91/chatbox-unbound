# chatbox-unbound

给 Chatbox（1.23.x 桌面版）用的解除限制插件。它改三处，全部可回滚：

1. **`settings.defaultPrompt`** —— 全局默认系统提示替换为解除限制指令（原值存档，随时还原）。新会话直接带上。
2. **技能** —— 在 `%APPDATA%\xyz.chatboxapp.app\skills\chatbox-unbound\SKILL.md` 落一个标准技能（frontmatter 符合 Chatbox 的 `parseSkillFile` 规则），并加进 `settings.skills.enabledSkillNames`。
3. **MCP 工具服务** —— 注册 `chatbox-unbound` 这个 stdio MCP 服务，提供 `unbound_status` / `unbound_directive` / `unbound_set_prompt` / `unbound_toggle` 四个工具。

## 双击就能用

桌面四个图标（工作区备份在 `desktop/`）：

| 图标 | 动作 |
| --- | --- |
| 1-开启解除限制.bat | 写 defaultPrompt、装技能、注册 MCP |
| 2-关闭解除限制.bat | 还原 defaultPrompt、删技能、摘 MCP |
| 3-查看状态.bat | 看三处是否命中 |
| 4-卸载.bat | 关闭 + 删除状态目录 |

开启后 **完全退出 Chatbox 再打开**（托盘退出，不是关窗口）。

## 命令行

```powershell
$node="$env:LOCALAPPDATA\Programs\DeepSeek Harness\resources\runtime\primary-runtime\dependencies\node\bin\node.exe"
$ins="C:\Users\Administrator.DESKTOP-1B8MNPO\Documents\deepseek-harness\default-workspace\chatbox-unbound\install.mjs"
& $node $ins --on
& $node $ins --off
& $node $ins --status
& $node $ins --uninstall
& $node $ins --app "D:\other\xyz.chatboxapp.app"     # 指定别的 userData
```

追加指令：写 `%APPDATA%\xyz.chatboxapp.app\chatbox-unbound\prompt.md`，下次 `--on` 时并在正文后面。

## 落盘

| 路径 | 内容 |
| --- | --- |
| `xyz.chatboxapp.app\config.json` | defaultPrompt / skills.enabledSkillNames / mcp.servers |
| `xyz.chatboxapp.app\skills\chatbox-unbound\SKILL.md` | 技能正文（含指令全文） |
| `xyz.chatboxapp.app\chatbox-unbound\state.json` | 开关、原始 prompt、备份路径 |
| `xyz.chatboxapp.app\chatbox-unbound\config-backup-*.json` | 每次改动前的配置快照 |

## 为什么必须重启

Chatbox 启动时把 `config.json` 读进内存，退出时按内存状态整体写回。所以：

- 先退出 Chatbox → 再双击「1-开启」→ 再打开，最稳。
- 运行中写入会被退出时的回写覆盖；此时「3-查看状态」会显示未注入，退出后重跑一次即可。

## 能力边界（重要）

Chatbox 只是客户端，模型来自你配置的 provider（DeepSeek / OpenAI / 本地模型……）。本插件改的是**发出去的会话上下文**（系统提示、技能、历史），因此：

- 对**本地模型或自部署端点**：效果完整，没有第二道闸。
- 对**云端 API**：模型看到的是完整指令、通常直接执行；但服务端自身若带审查层，仍可能在中途挡回。这不是插件能改的部分——客户端改不到服务端。

## 测试

```powershell
& $node test\test.mjs
```

覆盖：安装三处写入、关闭三处还原、MCP initialize / tools/list / tools/call / toggle 全链路。

## 桌面小人（pet）

`pet.ps1` 用 WinForms + `UpdateLayeredWindow` 画一个逐像素透明的置顶窗口：

- **拖拽**：左键按住移动，松手记住位置（`chatbox-unbound/pet-pos.txt`）。
- **q 弹**：按下压到 88%，松开跑阻尼弹簧回弹（`1 + amp·e^(-7t)·cos(15t)`，约 0.52 秒），底边固定不飘。
- **右键**：回到右下角 / 总在最前开关 / 退出。
- 开关随插件走：`--on` 自动拉起，`--off` / `--uninstall` 自动收起；也可单独用 `--pet` / `--no-pet`。

```powershell
& $node install.mjs --pet
& $node install.mjs --no-pet
```

图片用 `assets/hero-source.png`（原图，带背景；换图直接替换这个文件即可）。

## 发布

`publish-github.mjs` 走 GitHub Contents API，本机不需要 git：

```powershell
$env:GITHUB_TOKEN="ghp_xxx"   # 需要 repo 权限
& $node publish-github.mjs --repo chatbox-unbound
```

自动建仓库（已存在则复用）、逐个文件上传（已存在则按 sha 覆盖）。`--private` 建私有仓库，`--owner` 发到组织。

