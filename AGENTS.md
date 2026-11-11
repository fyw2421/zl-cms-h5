# AGENTS.md

本文件只记录分支与发布约定。功能、运行方式、接口口径见 `README.md`；接口契约以 `reference/` 下的 PC 端参考源现场核对为准，本文件不复述。

## 分支

| 分支 | 角色 |
| --- | --- |
| `main` | **只放发布版本**。每次发布一个 squash 提交，历史即发布日志 |
| `develop` | 日常开发，保留完整提交历史 |

## 铁律

- **只在 `develop` 上提交，永不直接改 `main`。** 紧急修复也一样：在 `develop` 上改，或从 `main` 开 hotfix 分支、修完合回 `develop`。原因：squash 后 `main` 与 `develop` 的提交**内容相同但 SHA 不同**，git 认为它们无关；在 `main` 上直接提交会让下次 squash 冲突。
- **把 `main` 同步回 `develop` 这一步不能省。** `merge --squash` 不会在 `develop` 留下「已合并」记录，不回灌的话下次 squash 会把旧改动重新当成新改动而冲突。

## 发布流程

> 联网（pull / push）前先确认代理可用，国内直连 GitHub 不稳：
> ```bash
> pwsh -File scripts/ensure-proxy.ps1         # 端口不通会自动拉起 dev-sidecar
> $env:HTTPS_PROXY = 'http://127.0.0.1:31181'  # 脚本不改 git config，代理由环境变量传入
> $env:HTTP_PROXY  = $env:HTTPS_PROXY
> ```
> 端口在听**不等于**代理能用（上游节点没连上时 git 仍报 `Failed to connect to github.com port 443 via 127.0.0.1`），所以脚本会穿过代理发一次真实请求再判定。每段命令在独立 shell 里执行时，代理环境变量不会保留。

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

## 发布物范围

- 提交里只放交付物 `zl-worklog.html` 与仓库文档/脚本。
- `reference/`（PC 端参考源）与 `_backup/`（修订前快照）**一律不入库**，已在 `.gitignore`；不要 `git add -f` 强加。
- 推送 `main` 会触发 `.github/workflows/pages.yml` 发布到 GitHub Pages（前提：仓库 Settings → Pages 的 Source 已设为 `GitHub Actions`）。该 workflow 只把 `zl-worklog.html` 复制成 `index.html` 上传，不要把其他文件或目录加进 `_site`。
