# AGENTS.md

本文件面向在此仓库工作的 AI 代理（以及接手的人类协作者）。它只记录**约定与验证流程**，功能与接口说明见 `README.md`。

## 仓库性质

- 产物是**一个** 离线单文件 HTML：`zl-worklog.html`。拷到手机浏览器打开即用，直接调公司 CMS 后端接口。
- 没有构建、没有依赖、没有测试框架、没有 package.json。不要引入 npm 包、构建工具或 npm 仓库结构。
- `reference/bundle.js`、`reference/worklog_component.js` 是 PC 端的**只读参考源**，用于核对接口契约，禁止修改、禁止移出 `reference/`。
- 根目录只放交付物与文档；参考资料一律进 `reference/`，不要把大文件扔在根目录。

## 目录

```
zl-worklog.html            # 唯一交付物，内联 CSS/JS
README.md                  # 功能与接口文档
AGENTS.md                  # 本文件
reference/
  bundle.js                # PC 端生产包（参考，勿改）
  worklog_component.js     # PC 端组件源码（参考，勿改）
_backup/                   # 历史快照，非交付产物（按需新建）
```

## 硬性约束

1. **单文件自包含**：CSS 必须在 `<style>` 内、JS 必须在 `<script>` 内；不得拆出 `.js` / `.css` / 额外 HTML，不得引用外部 CDN。
2. **原生 JS**：不用 React/Vue/JSX/Babel；状态用普通对象 + 重渲染函数。
3. **文件编码 UTF-8 无 BOM**；中文不要做任何转义或拼音化替换。
4. **接口契约不得臆造**：字段名、路径、时间格式必须回到 `reference/` 下的参考源现场核对，不要照 README 或记忆硬拼。可靠锚点是 `reference/bundle.js` 里的 `"/Worklog/`（一次列出全部日志接口）与 `baseURL`；**不要**依赖 `sft(` / `lft(` 这类压缩函数名，它们每次构建都会变。`reference/worklog_component.js` 里没有任何接口路径，只能用来核对字段与表单规则。
5. **窄屏优先**：CSS 为 375px 起写，桌面扩展放 `@media (min-width: 768px)`；正文 ≥14px，`input`/`textarea` ≥16px。
6. **不用 emoji**；图标用内联 SVG。`<meta name="viewport">` 必须含 `width=device-width, initial-scale=1`，禁止 `user-scalable=no`。
7. **禁止僵尸按钮**：任何看起来可点的元素必须有真实 handler 或明确反馈。
8. **只交付一个 `.html`**：`present_files` 的 `artifacts[].name` 用文件名本身，不另起标题，不附备份版。

## 不可破坏的既有行为（回归基线）

改动前先读这些实现，改动后必须仍然成立：

- **位置化提示**：`setNotice(key, type, msg)` 按 `my` / `dept` / `offline` / `general` 分槽，任一处渲染不得清掉其他来源的提示；登录页只用 `loginError()` 写 `#loginNotice`。
- **提交保护**：`state.myLogLoadedKey !== myLogKey()` 时 `#submitBtn` 必须置灰并给出原因——这是防止把当天已有日志覆盖成空表单的唯一防线。
- **部门归属**：`resolveSubmitDeptId()` 优先用登录返回的 `deptId`，缺失时才用 `state.submitDeptId`；「查看部门」只影响浏览，不影响提交归属。
- **提交体**：字段名与时间格式一律以 `reference/bundle.js` 为准，**本文件不复述**；不得凭记忆或旧文档构造请求体。可自检的部分只有一条：`workHours` 由时间段自动累加（1 位小数），不允许手工填写。
- **鉴权**：身份失效（凭证过期）→ 清凭证回登录页；无权限 → 仅提示，不动登录态。判定条件与 PC 端拦截器保持一致，以 `reference/bundle.js` 为准。
- **凭证时效**：`lw_h5_auth_v1` + `lw_h5_last_seen_v1`，闲置 3 天自动作废；判定点必须在 `api()` 发请求**之前**。
- **零工时**：`normal` 且工时 ≤0 时必须二次确认后才发请求。
- **校验顺序**：工作内容 → 时间段完整 → 5 分钟倍数 → 开始 < 结束 → 不交叉重复。

## 验证流程（每次改动都要跑）

环境：Windows，shell 为 PowerShell（`Bash` 工具在此主机不可用）。python 与 node 已安装。

### 1. 语法检查

```powershell
$p="C:\Users\ShenLan-Wai\Desktop\tmp\zl-cms-h5\zl-worklog.html"
$t=[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)
$i=$t.IndexOf('<script>'); $j=$t.LastIndexOf('</script>')
[IO.File]::WriteAllText("$env:TEMP\check.js",$t.Substring($i+8,$j-$i-8),(New-Object Text.UTF8Encoding $false))
node --check "$env:TEMP\check.js"; Write-Output "exit=$LASTEXITCODE"
```

`exit=0` 才算通过。**不要**用 PowerShell 管道或重定向写文件——会带上 BOM 或转成 UTF-16，导致 `node --check` 报无效字符。

### 2. 无头渲染

机器上只有 Edge（无 Chrome）：

```
C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
  --headless --disable-gpu --no-first-run --hide-scrollbars
  --virtual-time-budget=3000 --screenshot=<png> --window-size=600,1000
  --user-data-dir=%TEMP%\lwp_xxx  file:///<页面绝对路径，正斜杠>
```

要点：

- 用 Python 写脚本（`Write` 落 `.py` 再 `python xxx.py`），显式 `encoding='utf-8'`；状态注入方式是在 `</body>` 前插一段 `<script>`，在 `window.load` 里改 `state` 后调用对应 `render*` 函数。
- `--virtual-time-budget` 必须给，否则等不到异步结果落屏。
- 截图宽度可能小于 `--window-size`（工具侧裁切），**不要把截图裁切误判成布局溢出**；有疑问用页面内探针打印 `document.documentElement.scrollWidth` / `innerWidth` / `getBoundingClientRect()` 判定。
- 每个状态一张图，逐一 View 出来看，不能只看脚本说「成功」。至少要覆盖：登录校验提示、已加载可提交、未加载禁用、未绑定部门出现选择器、零工时确认、部门日志三态、提示分槽。

### 3. 端到端联通（可选）

需要验证 `file://` → 远程 API 是否仍通时，在页面内 `fetch` 一个需鉴权的接口：拿到业务 JSON 说明 CORS 与链路正常；页面停在「网络连接失败」或浏览器报跨域，则是 CORS 被收紧。用哪个接口、带什么参数，现场看页面里的 `api()` 调用点。

## 修改纪律

- **先备份**：结构性改动前把当前版本复制进 `_backup/`（命名 `zl-worklog-v2.html` 递增），备份不属于交付产物。
- **改已有文件**，不另建新版本文件；不要重命名用户已有的文件。
- **不要真的写入公司系统**：验证提交逻辑时只用注入状态 + 拦截，不要对 `SaveWorklog` / `SaveDeptWorklog` 发出真实成功请求。
- **不要动 `reference/` 下的两个参考源**，需要新契约就只读检索。
- 用户未要求的功能不要顺手加（撤销部门日志、截图导出、姓名筛选都在待办里，未经确认不要实现）。

## 交付

1. `node --check` 通过 + 关键状态渲染核对完毕；
2. `present_files` 只交付 `zl-worklog.html`（或本轮要交付的那一个文件）；
3. 回复说清「改了什么 / 用什么证据验证 / 还有什么没做」，不要只写「已完成」。

## 分支与发布

> **前置条件**：本仓库当前尚未 `git init`，也没有 `scripts/ensure-proxy.ps1`。本节流程在仓库接入 git 远端并提供该脚本之后才适用；在此之前，交付仍走上一节的 `present_files`。真到要用时，先确认脚本与远端确实存在，不要照抄命令去执行一个不存在的脚本。

| 分支 | 角色 |
| --- | --- |
| `main` | **只放发布版本**。每次发布一个 squash 提交，历史即发布日志 |
| `develop` | 日常开发，保留完整提交历史 |

### 铁律

- **只在 `develop` 上提交，永不直接改 `main`。** 紧急修复也一样：在 `develop` 上改，或从 `main` 开 hotfix 分支、修完合回 `develop`。原因：squash 后 `main` 与 `develop` 的提交**内容相同但 SHA 不同**，git 认为它们无关；在 `main` 上直接提交会让下次 squash 冲突。
- **第 6 步不能省。** `merge --squash` 不会在 `develop` 留下「已合并」记录，必须把 `main` 同步回 `develop`，否则下次 squash 会把旧改动重新当成新改动而冲突（已实测复现：`CONFLICT (content)`，因为找不到真正的共同祖先）。

### 发布流程

> ⚠ 第 1 步与第 5 步（要联网的）之前先跑代理检查，国内直连 GitHub 不稳：
> ```bash
> pwsh -File scripts/ensure-proxy.ps1        # 端口不通会自动拉起 dev-sidecar
> $env:HTTPS_PROXY = 'http://127.0.0.1:31181' # 脚本不改 git config，代理由环境变量传入
> $env:HTTP_PROXY  = $env:HTTPS_PROXY
> ```
> 端口在听**不等于**代理能用（上游节点没连上时 git 仍报 `Failed to connect to github.com port 443 via 127.0.0.1`），所以脚本会穿过代理发一次真实请求再判定。每段命令都在独立 shell 里执行时，代理环境变量不会保留，需重新设置。

```bash
# 1. 切到 main 并同步远端
git checkout main
git pull origin main

# 2. 把 develop 的全部改动压缩成一个提交
git merge --squash develop

# 3. 提交（写清这次发布了什么）
git commit -m "Release: 合并 develop 功能至 v1.1.0"

# 4. 打附注 tag（-a 而非轻量 tag：含作者/日期/说明，push --follow-tags 能带上）
git tag -a v1.1.0 -m "v1.1.0"

# 5. 推送 main 与 tag（CI 只在 push main 时触发部署）
git push origin main
git push origin v1.1.0

# 6. ★ 关键：把 main 同步回 develop，否则下次发布会冲突
git checkout develop
git merge main
git push origin develop
```

**tag 格式**：`vX.Y.Z`，附注 tag。首个是 `v1.0.0`。

发布提交里应包含交付物 `zl-worklog.html` 与本仓库文档；`_backup/` 与 `reference/` 按需决定是否入库（`reference/` 是只读参考源，体积较大，入库前确认远端是否接受）。

