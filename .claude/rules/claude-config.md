---
paths:
  - ".scripts/base/claude.ps1"
  - ".claude/settings.json"
  - ".claude/settings.local.json"
---

# Claude Code Configuration System

编辑 Claude Code 配置相关文件时加载。详细源码见 `.knowledge/claude_source_code/`。

## R10. CLAUDE_CONFIG — Claude Code 配置

Claude Code 配置系统（环境变量、settings.json、Profile）详见 `.scripts/base/claude.ps1`。

### 环境变量

Claude Code 通过 `claude.ps1` 的 `Set-DefaultConfig` 自动设置幂等环境变量（API_TIMEOUT_MS、DISABLE_*、BASH_*_TIMEOUT_MS、编码/区域等）。交互配置项（ANTHROPIC_AUTH_TOKEN、BASE_URL、模型名）通过 `omc setup claude` GUI 编辑器设置。所有环境变量存储在 User 级别。

### settings.json

`Set-ClaudeSettings` 幂等合并默认值到 `~/.claude/settings.json`：`permissions.allow/deny` 用 HashSet 去重合并，不覆盖用户手动添加的字段。

### Permission 规则格式

settings.json 中 `permissions.allow/deny` 使用以下格式：
- 精确匹配：`Bash(git status)` — 匹配完整命令
- 通配符：`Bash(git *)` — `*` 匹配任意字符，`\*` 匹配字面星号
- 工具级：`Read(*)` — 匹配该工具所有操作

### Profile 系统

Profile 存储在 `.config/claude/profiles/<Name>.json`，仅覆盖 Provider 相关配置（API 凭证、模型名、1M/thinking 开关）。通用配置不受 Profile 切换影响。

- `omc switch claude` — WinForms 对话框切换 Profile
- Active profile 标记在 `.config/claude/config.json` 的 `active_profile` 字段

### Hook 系统

Claude Code 支持 4 种 hook 类型：`command`（Shell 命令）、`prompt`（LLM 评估）、`http`（HTTP POST）、`agent`（智能体验证）。Hook 事件：`PreToolUse`、`PostToolUse`、`Stop`、`AssistantMessage`、`UserMessage` 等。配置在 settings.json 的 `hooks` 字段。

### MCP 服务器

配置在项目根目录 `.mcp.json` 的 `mcpServers` 字段，支持 `stdio`、`sse`、`http`、`ws` 传输类型。

### 插件系统

插件通过 marketplace 安装，marketplace 是 GitHub 仓库（如 `raystyle/claude-plugins`）。插件包含 skills、hooks、agents、commands 等组件。启用状态存储在 settings.json 的 `enabledPlugins` 字段（格式：`"plugin-name@marketplace": true`）。

### Skills 系统

Skills 是用户可调用的提示模板，存储在 `.claude/skills/` 目录。frontmatter 字段：`description`、`model`、`effort`、`user-invocable`、`allowed-tools`、`hooks` 等。
