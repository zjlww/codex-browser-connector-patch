# Codex Browser Connector Patch

这是一个面向 macOS 版 Codex / ChatGPT 桌面应用的本地兼容性补丁，用于在
Codex 使用 API Key、没有 ChatGPT 账号登录时恢复内置浏览器和 Chrome
连接器。

> 这不是 OpenAI 官方项目，也不受 OpenAI 支持。它通过修改应用包内的文件来
> 绕过认证、请求头策略和企业来源策略，可能导致应用签名失效、功能不稳定，
> 也可能不符合服务条款。请只在明确了解风险的前提下用于本机兼容性修复。

## 适用版本

本公开补丁的完整验证版本是：

```text
Codex Desktop / ChatGPT.app
CFBundleShortVersionString: 26.928.21956
```

适用范围说明：

- `26.928.21956`：已完整验证，包括内置浏览器导航和 Codex 原生 computer use。
- 更早版本：脚本中保留了旧的补丁 marker，但本公开版本没有重新验证旧应用。
- 更高或未知版本：不保证可用。Codex 更新通常会改变压缩后的 JavaScript、
  函数名和补丁点，必须重新执行 `--check` 并检查新的
  `browser-service.mjs`。
- 如果 `--check` 输出 `unknown`、`partial` 或 `--apply` 报告匹配数量异常，
  不要强行绕过错误，应先根据新版文件更新匹配规则。

> **重要提醒：** Codex 每次更新后，都应重新运行补丁检查。如果应用更新导致
> 补丁失效、出现新的安全门，或 `--check` 不再返回全部 `patched`，请回来更新
> 这个公开补丁后再继续使用。不要因为旧 marker 仍然存在就假定补丁仍然有效。

建议的更新处理流程：

1. 查看当前应用版本：

   ```sh
   defaults read /Applications/ChatGPT.app/Contents/Info CFBundleShortVersionString
   ```

2. 重新运行：

   ```sh
   python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
   ```

3. 如果结果不是全部 `patched`，在本仓库提交 issue 或 pull request，附上：
   - 当前 Codex 版本。
   - 完整错误信息。
   - `--check` 输出。
   - 新版 `browser-service.mjs` 中发生变化的错误字符串或函数片段。

4. 更新匹配规则并重新验证后，再发布新的补丁版本。

## 适用环境

- 系统：macOS
- 应用：`/Applications/ChatGPT.app`
- 需要系统自带的 `/usr/bin/python3`
- 默认不要求 root，但需要当前用户对应用目录有写权限

## 背景和问题原因

新版 Codex 桌面应用在以下四个位置会阻止无 ChatGPT 账号环境继续使用浏览器：

| 检查 | 常见错误 | 处理方式 |
| --- | --- | --- |
| 认证状态 | `Codex auth token is unavailable` | 用本地 shim 代理 `codex app-server`，只改写未登录的 `getAuthStatus` 响应 |
| 身份查询 | `User unavailable` | 把 `aura/identity` 查询替换为本地 synthetic user |
| 请求头策略 | `Unable to load browser request-header policy` | 关闭依赖 Statsig 的远程请求头开关 |
| 企业来源策略 | `The admin-enforced policy could not be verified` | `getOriginPolicyDecision()` 改为返回本地 `null`，不查询远端企业策略 |

这些检查的共同原因是：上游实现默认用户已经登录 ChatGPT，并且能够访问远程
身份、Statsig 和企业策略服务。API Key 或无账号模式下，任意一个检查失败都会
按 fail-closed 设计终止浏览器操作。

旧版本补丁只处理了：

- `getAuthStatus` 没有认证 token。
- `chatgpt.com/backend-api/aura/identity` 返回 `User unavailable`。

`26.928.21956` 又增加了 Statsig 请求头策略和企业来源策略检查。因此旧补丁即使
已经应用，仍会在导航前失败。补丁脚本现在还会识别 `partial`，避免把只完成旧
版本修补的文件误报为完全可用。

## 补丁具体做了什么

### 1. 替换 `node_repl` 启动入口

原始二进制会被保留为：

```text
/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl-vendor
```

新的 `node_repl` 是一个很小的 shell wrapper。它只对 Codex 的 node runtime
设置 `CODEX_CLI_PATH`，指向本地 `codex-auth-shim.py`。应用自己的 app-server
仍然使用原始 Codex CLI，不受影响。

### 2. 用 shim 改写本地认证状态

`codex-auth-shim.py` 启动真实 Codex CLI，并转发它的 JSON-RPC 消息。唯一改动
是：当真实 CLI 返回未登录的 `getAuthStatus` 时，shim 返回一个本地的
`chatgpt` synthetic token。

这个 token 只用于通过本地 node runtime 的检查。shim 不会把账号、密码、Cookie
或用户凭据写入仓库。

### 3. 修复浏览器 service 的四个检查

`patch-browser-connector.py` 会修改应用包和插件缓存中的
`browser-service.mjs`：

1. `getAuthStatus` 由 wrapper 和 shim 处理。
2. `aura/identity` 查询替换成 synthetic user。
3. Statsig 请求头 gate 直接返回 `false`。
4. `getOriginPolicyDecision()` 返回本地 `null`，不再查询远端企业策略。

所有原始文件会先备份到 `appbundle-orig/`，并写入 marker，便于 `--check` 判断
完整、部分或未知状态。

## 安全边界

- 脚本不会写入 ChatGPT 用户名、密码、Cookie 或 API Key。
- `codex-auth-shim.py` 只在本地生成一个 synthetic token，用于通过应用内部检查。
- Gate 4 会绕过应用的企业来源策略。每站点的持久化用户授权逻辑仍然存在，
  但管理端来源策略不再作为导航条件。
- 修改后应用签名会失效，这是补丁生效的预期结果。
- 每次应用更新都可能覆盖这些文件，需要重新执行 `--check` 和 `--apply`。

## 为什么需要完整重启应用

Codex 的浏览器 service 是长时间驻留的进程。修改磁盘上的
`browser-service.mjs` 或 `node_repl` 后，仅调用 `js_reset` 不会替换已经加载
旧代码的 service supervisor。必须完整退出并重新启动 `ChatGPT.app`，新进程
才会从磁盘加载补丁版本。

## 使用方法

### 1. 克隆仓库

```sh
git clone https://github.com/zjlww/codex-browser-connector-patch.git
cd codex-browser-connector-patch
```

### 2. 部署辅助脚本

```sh
bash scripts/deploy.sh
```

脚本默认部署到：

```text
~/.local/share/codex-rollback/
```

### 3. 检查状态

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

退出码为 `0` 表示全部目标已经修补。`partial` 表示只应用了部分版本，
`unknown` 表示应用包结构发生变化，需要更新匹配规则。

### 4. 应用补丁

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --apply
```

应用前会把原始文件备份到：

```text
~/.local/share/codex-rollback/appbundle-orig/
```

### 5. 完整重启应用

必须完整退出并重新启动 `ChatGPT.app`。仅重置 Codex 的 JavaScript 会话
不会替换已经驻留的浏览器 service 进程。

```sh
python3 -c "import subprocess;subprocess.Popen(['/bin/bash','$HOME/.local/share/codex-rollback/restart-once.sh'],start_new_session=True)"
```

### 6. 验证

在 Codex 会话中执行：

```js
await cua.getState();
const tab = await cua.createBrowserTab("iab", "https://example.com");
await tab.getAXState();
```

预期结果：

- 浏览器列表中包含 Chrome 和 Codex In-app Browser。
- 内置浏览器能够打开 `https://example.com`。
- `getAXState()` 返回 Example Domain 页面内容。

## 恢复原状

```sh
bash ~/.local/share/codex-rollback/restore-appbundle.sh
```

然后重新启动应用。恢复脚本会：

- 从 `appbundle-orig/` 恢复 `browser-service.mjs`。
- 把 `node_repl-vendor` 恢复为原始的 `node_repl`。
- 保留备份文件，便于再次检查。

如果恢复后仍不正常，可从官方安装包重新安装应用。

## 可配置环境变量

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `CHATGPT_APP` | `/Applications/ChatGPT.app` | 应用路径 |
| `CODEX_BROWSER_ROLLBACK_DIR` | `~/.local/share/codex-rollback` | 备份和辅助脚本目录 |
| `CODEX_HOME` | `~/.codex` | Codex 配置和插件缓存目录 |
| `CODEX_AUTH_SHIM_REAL_CLI` | 应用内 `codex` 可执行文件 | shim 代理的真实 CLI |

## 目录结构

```text
.
├── README.md
└── scripts
    ├── codex-auth-shim.py
    ├── deploy.sh
    ├── patch-browser-connector.py
    ├── restart-once.sh
    └── restore-appbundle.sh
```

## 应用更新后如何适配

新版 Codex 通常会：

- 移动或重命名压缩后的 JavaScript 函数。
- 增加新的 fail-closed 安全检查。
- 让旧 marker 仍然存在，但运行路径已经变化。

出现以下情况时需要更新匹配规则：

```sh
python3 ~/.local/share/codex-rollback/patch-browser-connector.py --check
```

如果输出不是稳定的 `patched`，请检查新版
`browser-service.mjs` 和 `cua_node/bin/node_repl`，再更新
[`scripts/patch-browser-connector.py`](scripts/patch-browser-connector.py)
中的路径、marker 和正则表达式。

## 已知限制

- 补丁针对特定 Codex 版本的 minified JavaScript，版本变化后需要重新验证。
- 只验证了内置浏览器；Chrome 扩展导航未在每次测试中单独执行。
- Gate 4 会绕过企业来源策略。
- 修改应用包会破坏代码签名。
- 不保证未来版本仍可使用相同的补丁点。

## 许可证

MIT
