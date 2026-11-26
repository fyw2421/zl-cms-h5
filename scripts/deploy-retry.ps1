<#
.SYNOPSIS
  重跑最近一次（或指定的）Pages 部署，替代「往 main 推空提交」这种污染发布历史的重试方式。

.DESCRIPTION
  调 GitHub REST：POST /repos/{repo}/actions/runs/{id}/rerun。
  只重跑 workflow，不改仓库内容，因此 main 上不会再出现 chore 提交。

  需要环境变量 GITHUB_TOKEN：classic token 勾 repo 即可（要 Actions: read & write）。

.PARAMETER RunId
  要重跑的 run id。省略时配合 -Latest 使用。

.PARAMETER Latest
  重跑 main 分支最近一次 run（不管它成功与否）。

.PARAMETER List
  只看不跑：列出 main 分支最近 N 次 run 的 id / 状态 / 结论 / commit。

.EXAMPLE
  $env:HTTPS_PROXY='http://127.0.0.1:31181'   # 国内直连不稳时
  $env:GITHUB_TOKEN='ghp_...'
  pwsh -File scripts/deploy-retry.ps1 -List 5

.EXAMPLE
  pwsh -File scripts/deploy-retry.ps1 -Latest
#>
param(
  [string]$Repo = 'fyw2421/zl-cms-h5',
  [long]$RunId = 0,
  [switch]$Latest,
  [int]$List = 0
)

$ErrorActionPreference = 'Stop'
$token = $env:GITHUB_TOKEN
if (-not $token) {
  Write-Output '缺少 $env:GITHUB_TOKEN：请在 GitHub → Settings → Developer settings 生成 classic token（勾 repo），再设置到环境变量'
  exit 1
}
$headers = @{
  Authorization = "Bearer $token"
  Accept        = 'application/vnd.github+json'
  'User-Agent'  = 'zl-cms-h5-deploy-retry'
}

function Show-Runs([int]$count) {
  $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs?branch=main&per_page=$count" -Headers $headers
  foreach ($r in $resp.workflow_runs) {
    '{0}  {1,-9} {2,-9} {3}  {4}' -f $r.id, $r.status, ($r.conclusion ?? '-'), $r.head_sha.Substring(0, 7), $r.created_at
  }
}

if ($List -gt 0) { Show-Runs $List; exit 0 }

if ($RunId -eq 0) {
  if (-not $Latest) {
    Write-Output '没指定要重跑的 run。先看列表：'
    Show-Runs 5
    Write-Output ''
    Write-Output '再执行：pwsh -File scripts/deploy-retry.ps1 -Latest   或   -RunId <上面第一列的 id>'
    exit 0
  }
  $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/actions/runs?branch=main&per_page=1" -Headers $headers
  $RunId = $resp.workflow_runs[0].id
}

Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/actions/runs/$RunId/rerun" -Headers $headers | Out-Null
Write-Output "已请求重跑 run $RunId；打开 https://github.com/$Repo/actions 看结果"
